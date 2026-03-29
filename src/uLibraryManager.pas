unit uLibraryManager;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Process, strutils, uConfig, uAudioNormalizer;

type
  TFileAction = (faConvert, faBackup, faMoveHiRes, faMoveCDQuality, faMoveWav, faMoveMp3);

  TFilePipeline = record
    OriginalFile: string;
    Actions: array of TFileAction;
    FinalDest: string;
    BackupDest: string;
  end;

  TLibraryManager = class
  private
    FPipelines: array of TFilePipeline;
    FDoConvert: Boolean;
    FDoMove: Boolean;
    function GetBitDepth(const FilePath: string): Integer;
    procedure AddAction(var Pipeline: TFilePipeline; Action: TFileAction);
    function ActionToStr(Action: TFileAction): string;
    procedure ScanDirectory(const DirPath, RelativePath: string);
  public
    constructor Create(DoConvert, DoMove: Boolean);
    procedure BuildPipeline;
    procedure PrintDryRun;
    procedure ExecutePipeline;
  end;

implementation

constructor TLibraryManager.Create(DoConvert, DoMove: Boolean);
begin
  FDoConvert := DoConvert;
  FDoMove := DoMove;
  SetLength(FPipelines, 0);
end;

procedure TLibraryManager.AddAction(var Pipeline: TFilePipeline; Action: TFileAction);
begin
  SetLength(Pipeline.Actions, Length(Pipeline.Actions) + 1);
  Pipeline.Actions[High(Pipeline.Actions)] := Action;
end;

function TLibraryManager.ActionToStr(Action: TFileAction): string;
begin
  case Action of
    faConvert: Result := 'Convert to ' + UpperCase(AppConfig.OutputCodec);
    faBackup: Result := 'Backup Original';
    faMoveHiRes: Result := 'Move to Hi-Res';
    faMoveCDQuality: Result := 'Move to CD Quality';
    faMoveWav: Result := 'Move to WAV';
    faMoveMp3: Result := 'Move to MP3';
  else
    Result := 'Unknown Action';
  end;
end;

function TLibraryManager.GetBitDepth(const FilePath: string): Integer;
var
  Proc: TProcess;
  OutputStr: string;
  MemStream: TMemoryStream;
  BytesRead: LongInt;
  Buffer: array[0..2047] of Byte;
begin
  Result := 16; // Default to 16-bit
  Proc := TProcess.Create(nil);
  MemStream := TMemoryStream.Create;
  try
    Proc.Executable := AppConfig.FFMpegPath;
    // We use ffprobe which is usually in the same directory as ffmpeg
    Proc.Executable := StringReplace(Proc.Executable, 'ffmpeg', 'ffprobe', [rfIgnoreCase]);
    
    Proc.Parameters.Add('-v');
    Proc.Parameters.Add('error');
    Proc.Parameters.Add('-select_streams');
    Proc.Parameters.Add('a:0');
    Proc.Parameters.Add('-show_entries');
    Proc.Parameters.Add('stream=sample_fmt');
    Proc.Parameters.Add('-of');
    Proc.Parameters.Add('default=noprint_wrappers=1:nokey=1');
    Proc.Parameters.Add(FilePath);
    
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

    OutputStr := Trim(OutputStr);
    
    if (Pos('24', OutputStr) > 0) or (Pos('32', OutputStr) > 0) then
      Result := 24;

  finally
    Proc.Free;
    MemStream.Free;
  end;
end;

procedure TLibraryManager.ScanDirectory(const DirPath, RelativePath: string);
var
  SearchRec: TSearchRec;
  Ext, FileName, FullPath, NewRelativePath: string;
  Pipeline: TFilePipeline;
  BitDepth: Integer;
begin
  if FindFirst(IncludeTrailingPathDelimiter(DirPath) + '*.*', faAnyFile, SearchRec) = 0 then
  begin
    try
      repeat
        FileName := SearchRec.Name;
        if (FileName = '.') or (FileName = '..') then Continue;

        FullPath := IncludeTrailingPathDelimiter(DirPath) + FileName;

        if (SearchRec.Attr and faDirectory) = faDirectory then
        begin
          NewRelativePath := IncludeTrailingPathDelimiter(RelativePath + FileName);
          ScanDirectory(FullPath, NewRelativePath);
        end
        else
        begin
          Ext := LowerCase(ExtractFileExt(FileName));
          Pipeline.OriginalFile := FullPath;
          SetLength(Pipeline.Actions, 0);
          Pipeline.FinalDest := '';
          Pipeline.BackupDest := '';

          if (Ext = '.m4a') and FDoConvert then
          begin
            AddAction(Pipeline, faConvert);
            AddAction(Pipeline, faBackup);
            Pipeline.BackupDest := IncludeTrailingPathDelimiter(AppConfig.BackupM4APath) + RelativePath + FileName;
            
            if FDoMove then
            begin
              // Converted files inherit the AppConfig settings
              if (Pos('24', AppConfig.SampleFormat) > 0) or (Pos('32', AppConfig.SampleFormat) > 0) then
              begin
                AddAction(Pipeline, faMoveHiRes);
                Pipeline.FinalDest := IncludeTrailingPathDelimiter(AppConfig.HiResPath) + RelativePath + ChangeFileExt(FileName, '.' + AppConfig.OutputCodec);
              end
              else
              begin
                AddAction(Pipeline, faMoveCDQuality);
                Pipeline.FinalDest := IncludeTrailingPathDelimiter(AppConfig.CDQualityPath) + RelativePath + ChangeFileExt(FileName, '.' + AppConfig.OutputCodec);
              end;
            end;
            
            SetLength(FPipelines, Length(FPipelines) + 1);
            FPipelines[High(FPipelines)] := Pipeline;
          end
          else if FDoMove then
          begin
            if (Ext = '.flac') or (Ext = '.alac') then
            begin
              BitDepth := GetBitDepth(Pipeline.OriginalFile);
              if BitDepth >= 24 then
              begin
                AddAction(Pipeline, faMoveHiRes);
                Pipeline.FinalDest := IncludeTrailingPathDelimiter(AppConfig.HiResPath) + RelativePath + FileName;
              end
              else
              begin
                AddAction(Pipeline, faMoveCDQuality);
                Pipeline.FinalDest := IncludeTrailingPathDelimiter(AppConfig.CDQualityPath) + RelativePath + FileName;
              end;
            end
            else if Ext = '.wav' then
            begin
              AddAction(Pipeline, faMoveWav);
              Pipeline.FinalDest := IncludeTrailingPathDelimiter(AppConfig.WavPath) + RelativePath + FileName;
            end
            else if Ext = '.mp3' then
            begin
              AddAction(Pipeline, faMoveMp3);
              Pipeline.FinalDest := IncludeTrailingPathDelimiter(AppConfig.Mp3Path) + RelativePath + FileName;
            end;

            if Length(Pipeline.Actions) > 0 then
            begin
              SetLength(FPipelines, Length(FPipelines) + 1);
              FPipelines[High(FPipelines)] := Pipeline;
            end;
          end;
        end;
      until FindNext(SearchRec) <> 0;
    finally
      FindClose(SearchRec);
    end;
  end;
end;

procedure TLibraryManager.BuildPipeline;
begin
  SetLength(FPipelines, 0);

  if not DirectoryExists(AppConfig.InputPath) then
  begin
    WriteLn('Input path does not exist: ', AppConfig.InputPath);
    Exit;
  end;

  ScanDirectory(AppConfig.InputPath, '');
end;

procedure TLibraryManager.PrintDryRun;
var
  i, j: Integer;
  ActionStr: string;
begin
  WriteLn('--- DRY RUN: Library Management Plan ---');
  if Length(FPipelines) = 0 then
  begin
    WriteLn('No files found requiring action.');
    Exit;
  end;

  for i := 0 to High(FPipelines) do
  begin
    WriteLn('File: ', ExtractFileName(FPipelines[i].OriginalFile));
    ActionStr := '  Pipeline: ';
    for j := 0 to High(FPipelines[i].Actions) do
    begin
      ActionStr := ActionStr + ActionToStr(FPipelines[i].Actions[j]);
      if j < High(FPipelines[i].Actions) then
        ActionStr := ActionStr + ' -> ';
    end;
    WriteLn(ActionStr);
    
    if FPipelines[i].BackupDest <> '' then
      WriteLn('  Backup -> ', FPipelines[i].BackupDest);
    if FPipelines[i].FinalDest <> '' then
      WriteLn('  Target -> ', FPipelines[i].FinalDest);
      
    WriteLn('');
  end;
  WriteLn('Total files to process: ', Length(FPipelines));
  WriteLn('----------------------------------------');
end;

procedure TLibraryManager.ExecutePipeline;
var
  i, j: Integer;
  Pl: TFilePipeline;
  CurrentFile, TempFile: string;
begin
  if Length(FPipelines) = 0 then Exit;

  WriteLn('Executing Pipeline...');

  for i := 0 to High(FPipelines) do
  begin
    Pl := FPipelines[i];
    CurrentFile := Pl.OriginalFile;
    WriteLn('Processing: ', ExtractFileName(CurrentFile));

    for j := 0 to High(Pl.Actions) do
    begin
      case Pl.Actions[j] of
        faConvert:
        begin
          WriteLn('  -> Converting...');
          if ConvertM4AToFlacTwoPass(CurrentFile) then
            TempFile := ChangeFileExt(CurrentFile, '.' + AppConfig.OutputCodec)
          else
          begin
            WriteLn('  -> Conversion failed. Skipping rest of pipeline.');
            Break; // Stop pipeline for this file
          end;
        end;
        faBackup:
        begin
          WriteLn('  -> Backing up original...');
          ForceDirectories(ExtractFilePath(Pl.BackupDest));
          if RenameFile(CurrentFile, Pl.BackupDest) then
          begin
            // Since original is moved, the active file is now the converted one
            CurrentFile := TempFile; 
          end;
        end;
        faMoveHiRes, faMoveCDQuality, faMoveWav, faMoveMp3:
        begin
          WriteLn('  -> Moving to library...');
          ForceDirectories(ExtractFilePath(Pl.FinalDest));
          if RenameFile(CurrentFile, Pl.FinalDest) then
            WriteLn('  -> Done.')
          else
            WriteLn('  -> Move failed.');
        end;
      end;
    end;
  end;
  WriteLn('Pipeline execution finished.');
end;

end.