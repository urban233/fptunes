unit uAudioNormalizer;

{$mode objfpc}{$H+} 

interface

uses
  Classes, SysUtils, Process, fpjson, jsonparser, strutils, uConfig;

// This is the only function exposed to the rest of the application
function ConvertM4AToFlacTwoPass(const InputPath, OutputPath: string): Boolean;
function ConvertM4AToFlacTruePeak(const InputPath, OutputPath: string): Boolean;

implementation

// ============================================================================
// HELPER: True Peak Normalization (One-Pass)
// ============================================================================
function ConvertM4AToFlacTruePeak(const InputPath, OutputPath: string): Boolean;
var
  Proc: TProcess;
begin
  Result := False;
  Writeln('Starting True-Peak Normalization for: ', ExtractFileName(InputPath));
  Writeln(Format('  -> Applying true-peak limiter and exporting to %s...', [AppConfig.OutputCodec]));

  Proc := TProcess.Create(nil);
  try
    Proc.Executable := AppConfig.FFMpegPath;
    Proc.Parameters.Add('-hide_banner');
    Proc.Parameters.Add('-y'); 
    Proc.Parameters.Add('-i');
    Proc.Parameters.Add(InputPath);
    Proc.Parameters.Add('-af');
    // aresample=resampler=soxr (high quality resampling to prevent inter-sample peaks)
    // alimiter=limit=0.9885 (-0.1 dB True Peak limit)
    Proc.Parameters.Add('aresample=resampler=soxr,alimiter=limit=0.9885');
    Proc.Parameters.Add('-map_metadata');
    Proc.Parameters.Add('0');
    Proc.Parameters.Add('-c:a');
    Proc.Parameters.Add(AppConfig.OutputCodec);
    Proc.Parameters.Add('-sample_fmt');
    Proc.Parameters.Add(AppConfig.SampleFormat); 
    Proc.Parameters.Add('-ar');
    Proc.Parameters.Add(IntToStr(AppConfig.SampleRate));
    Proc.Parameters.Add('-compression_level');
    Proc.Parameters.Add(IntToStr(AppConfig.CompressionLevel));
    Proc.Parameters.Add(OutputPath);

    Proc.Options := [poWaitOnExit];
    Proc.Execute;

    if Proc.ExitStatus = 0 then
    begin
      Writeln('  -> Success! File saved: ', OutputPath);
      Result := True;
    end
    else
      Writeln('  -> Error: ffmpeg encountered an error during True-Peak conversion.');
  finally
    Proc.Free;
  end;
end;

// ============================================================================
// HELPER 1: Run Pass 1 to analyze the audio and capture the JSON output
// ============================================================================
function AnalyzeAudio(const FilePath: string; out CapturedJSON: string): Boolean;
var
  Proc: TProcess;
  MemStream: TMemoryStream;
  Buffer: array[0..2047] of Byte;
  BytesRead: LongInt;
  OutputStr: string;
  JsonStart, JsonEnd: Integer;
  FormatSettings: TFormatSettings;
begin
  Result := False;
  CapturedJSON := '';
  Proc := TProcess.Create(nil);
  MemStream := TMemoryStream.Create;
  
  FormatSettings := DefaultFormatSettings;
  FormatSettings.DecimalSeparator := '.';
  
  try
    Proc.Executable := AppConfig.FFMpegPath;
    Proc.Parameters.Add('-hide_banner');
    Proc.Parameters.Add('-i');
    Proc.Parameters.Add(FilePath);
    Proc.Parameters.Add('-af');
    Proc.Parameters.Add(Format('loudnorm=I=%s:LRA=%s:TP=%s:print_format=json', 
      [FloatToStr(AppConfig.TargetLUFS, FormatSettings), 
       FloatToStr(AppConfig.TargetLRA, FormatSettings), 
       FloatToStr(AppConfig.TargetTP, FormatSettings)]));
    Proc.Parameters.Add('-f');
    Proc.Parameters.Add('null');
    Proc.Parameters.Add('-');
    
    // Capture the output dynamically
    Proc.Options := [poUsePipes, poStderrToOutPut];
    Proc.Execute;

    while Proc.Running do
    begin
      BytesRead := Proc.Output.Read(Buffer, SizeOf(Buffer));
      if BytesRead > 0 then MemStream.Write(Buffer, BytesRead)
      else Sleep(50);
    end;
    
    repeat
      BytesRead := Proc.Output.Read(Buffer, SizeOf(Buffer));
      if BytesRead > 0 then MemStream.Write(Buffer, BytesRead);
    until BytesRead <= 0;

    SetLength(OutputStr, MemStream.Size);
    MemStream.Position := 0;
    if MemStream.Size > 0 then
      MemStream.ReadBuffer(Pointer(OutputStr)^, MemStream.Size);

    // Extract JSON block from the raw ffmpeg output
    JsonStart := RPos('{', OutputStr);
    JsonEnd := RPos('}', OutputStr);
    
    if (JsonStart > 0) and (JsonEnd > JsonStart) then
    begin
      CapturedJSON := Copy(OutputStr, JsonStart, JsonEnd - JsonStart + 1);
      Result := True;
    end;
  finally
    Proc.Free;
    MemStream.Free;
  end;
end;

// ============================================================================
// HELPER 2: Parse the JSON string and build the massive filter string
// ============================================================================
function BuildFilterString(const JsonStr: string; out FilterStr: string): Boolean;
var
  JsonData: TJSONData;
  JObj: TJSONObject;
  FormatSettings: TFormatSettings;
begin
  Result := False;
  FormatSettings := DefaultFormatSettings;
  FormatSettings.DecimalSeparator := '.';
  
  try
    JsonData := GetJSON(JsonStr);
    JObj := TJSONObject(JsonData);
    
    FilterStr := Format('loudnorm=I=%s:LRA=%s:TP=%s:measured_I=%s:measured_LRA=%s:measured_TP=%s:measured_thresh=%s:offset=%s',
      [FloatToStr(AppConfig.TargetLUFS, FormatSettings),
       FloatToStr(AppConfig.TargetLRA, FormatSettings),
       FloatToStr(AppConfig.TargetTP, FormatSettings),
       JObj.Strings['input_i'],
       JObj.Strings['input_lra'],
       JObj.Strings['input_tp'],
       JObj.Strings['input_thresh'],
       JObj.Strings['target_offset']]);
       
    Result := True;
  finally
    JsonData.Free;
  end;
end;

// ============================================================================
// HELPER 3: Run Pass 2 to apply the filter and export the FLAC
// ============================================================================
function ApplyNormalization(const InputPath, OutputPath, FilterStr: string): Boolean;
var
  Proc: TProcess;
begin
  Result := False;
  Proc := TProcess.Create(nil);
  try
    Proc.Executable := AppConfig.FFMpegPath;
    Proc.Parameters.Add('-hide_banner');
    Proc.Parameters.Add('-y'); 
    Proc.Parameters.Add('-i');
    Proc.Parameters.Add(InputPath);
    Proc.Parameters.Add('-af');
    Proc.Parameters.Add(FilterStr);
    Proc.Parameters.Add('-map_metadata');
    Proc.Parameters.Add('0');
    Proc.Parameters.Add('-c:a');
    Proc.Parameters.Add(AppConfig.OutputCodec);
    Proc.Parameters.Add('-sample_fmt');
    Proc.Parameters.Add(AppConfig.SampleFormat); 
    Proc.Parameters.Add('-ar');
    Proc.Parameters.Add(IntToStr(AppConfig.SampleRate));
    Proc.Parameters.Add('-compression_level');
    Proc.Parameters.Add(IntToStr(AppConfig.CompressionLevel));
    Proc.Parameters.Add(OutputPath);

    Proc.Options := [poWaitOnExit];
    Proc.Execute;

    Result := (Proc.ExitStatus = 0);
  finally
    Proc.Free;
  end;
end;

// ============================================================================
// MAIN WRAPPER: This strings the helpers together cleanly
// ============================================================================
function ConvertM4AToFlacTwoPass(const InputPath, OutputPath: string): Boolean;
var
  JsonStr, FilterStr: string;
begin
  Result := False;
  Writeln('Starting Two-Pass Normalization for: ', ExtractFileName(InputPath));

  Writeln('  -> Pass 1: Analyzing audio dynamics...');
  if not AnalyzeAudio(InputPath, JsonStr) then
  begin
    Writeln('  -> Error: Failed to analyze audio or extract JSON.');
    Exit;
  end;

  if not BuildFilterString(JsonStr, FilterStr) then
  begin
    Writeln('  -> Error: Failed to parse analysis data.');
    Exit;
  end;

  Writeln(Format('  -> Pass 2: Applying measured filters and exporting to %s...', [AppConfig.OutputCodec]));
  if ApplyNormalization(InputPath, OutputPath, FilterStr) then
  begin
    Writeln('  -> Success! File saved: ', OutputPath);
    Result := True;
  end
  else
    Writeln('  -> Error: ffmpeg encountered an error during Pass 2.');
end;

end.
