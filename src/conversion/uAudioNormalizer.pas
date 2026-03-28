unit uAudioNormalizer;

{$mode objfpc}{$H+} 

interface

uses
  Classes, SysUtils, Process, fpjson, jsonparser, strutils;

// This is the only function exposed to the rest of the application
function ConvertM4AToFlacTwoPass(const InputPath: string): Boolean;

implementation

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
begin
  Result := False;
  CapturedJSON := '';
  Proc := TProcess.Create(nil);
  MemStream := TMemoryStream.Create;
  try
    Proc.Executable := 'ffmpeg';
    Proc.Parameters.Add('-hide_banner');
    Proc.Parameters.Add('-i');
    Proc.Parameters.Add(FilePath);
    Proc.Parameters.Add('-af');
    Proc.Parameters.Add('loudnorm=I=-14:LRA=11:TP=-1.0:print_format=json');
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
begin
  Result := False;
  try
    JsonData := GetJSON(JsonStr);
    JObj := TJSONObject(JsonData);
    
    FilterStr := Format('loudnorm=I=-14:LRA=11:TP=-1.0:measured_I=%s:measured_LRA=%s:measured_TP=%s:measured_thresh=%s:offset=%s',
      [JObj.Strings['input_i'],
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
    Proc.Executable := 'ffmpeg';
    Proc.Parameters.Add('-hide_banner');
    Proc.Parameters.Add('-y'); 
    Proc.Parameters.Add('-i');
    Proc.Parameters.Add(InputPath);
    Proc.Parameters.Add('-af');
    Proc.Parameters.Add(FilterStr);
    Proc.Parameters.Add('-c:a');
    Proc.Parameters.Add('flac');
    Proc.Parameters.Add('-sample_fmt');
    Proc.Parameters.Add('s24'); 
    Proc.Parameters.Add('-ar');
    Proc.Parameters.Add('44100');
    Proc.Parameters.Add('-compression_level');
    Proc.Parameters.Add('8');
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
function ConvertM4AToFlacTwoPass(const InputPath: string): Boolean;
var
  JsonStr, FilterStr, FlacPath: string;
begin
  Result := False;
  FlacPath := ChangeFileExt(InputPath, '.flac');
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

  Writeln('  -> Pass 2: Applying measured filters and exporting to 24-bit FLAC...');
  if ApplyNormalization(InputPath, FlacPath, FilterStr) then
  begin
    Writeln('  -> Success! File saved: ', FlacPath);
    Result := True;
  end
  else
    Writeln('  -> Error: ffmpeg encountered an error during Pass 2.');
end;

end.
