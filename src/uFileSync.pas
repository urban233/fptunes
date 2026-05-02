unit uFileSync;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, DateUtils, Classes, fpmasks, uConfig;

type
  TSyncAction = (saCopy, saUpdate, saDelete, saSkip);

  TSyncOperation = record
    SrcPath: string;
    DestPath: string;
    Action: TSyncAction;
    IsDirectory: Boolean;
    Reason: string;
  end;

  TFileSyncManager = class
  private
    FOperations: array of TSyncOperation;
    FSourcePath: string;
    FDestPath: string;
    FExclusions: TStringList;

    function IsExcluded(const ItemName: string): Boolean;
    function DeleteDirRec(const Dir: string): Boolean;
    function CopyFileSafe(const Source, Dest: string): Boolean;
    function FilesAreIdentical(const SrcFile, DestFile: string): Boolean;
    procedure AddOperation(const Src, Dest: string; AAction: TSyncAction; IsDir: Boolean; const AReason: string);
    procedure BuildMirrorPhase(const SrcRoot, DestRoot: string);
    procedure BuildSyncPhase(const SrcRoot, DestRoot: string);
  public
    constructor Create(const ASource, ADest: string);
    destructor Destroy; override;
    procedure BuildPipeline;
    procedure PrintDryRun;
    procedure ExecutePipeline;
  end;

implementation

constructor TFileSyncManager.Create(const ASource, ADest: string);
begin
  FSourcePath := IncludeTrailingPathDelimiter(ASource);
  FDestPath := IncludeTrailingPathDelimiter(ADest);
  FExclusions := TStringList.Create;
  // Default exclusions
  FExclusions.Add('.git');
  FExclusions.Add('*.tmp');
  FExclusions.Add('~*');
  FExclusions.Add('__pycache__');
  FExclusions.Add('node_modules');
  SetLength(FOperations, 0);
end;

destructor TFileSyncManager.Destroy;
begin
  FExclusions.Free;
  inherited Destroy;
end;

function TFileSyncManager.IsExcluded(const ItemName: string): Boolean;
var
  i: Integer;
begin
  Result := False;
  for i := 0 to FExclusions.Count - 1 do
  begin
    if MatchesMask(ItemName, FExclusions[i]) then
    begin
      Result := True;
      Exit;
    end;
  end;
end;

procedure TFileSyncManager.AddOperation(const Src, Dest: string; AAction: TSyncAction; IsDir: Boolean; const AReason: string);
begin
  SetLength(FOperations, Length(FOperations) + 1);
  FOperations[High(FOperations)].SrcPath := Src;
  FOperations[High(FOperations)].DestPath := Dest;
  FOperations[High(FOperations)].Action := AAction;
  FOperations[High(FOperations)].IsDirectory := IsDir;
  FOperations[High(FOperations)].Reason := AReason;
end;

function TFileSyncManager.DeleteDirRec(const Dir: string): Boolean;
var
  SR: TSearchRec;
  ItemPath: string;
begin
  Result := True;
  if FindFirst(IncludeTrailingPathDelimiter(Dir) + '*', faAnyFile, SR) = 0 then
  begin
    try
      repeat
        if (SR.Name = '.') or (SR.Name = '..') then Continue;
        ItemPath := IncludeTrailingPathDelimiter(Dir) + SR.Name;
        FileSetAttr(ItemPath, 0); 
        if (SR.Attr and faDirectory) <> 0 then
          DeleteDirRec(ItemPath)
        else
          DeleteFile(ItemPath);
      until FindNext(SR) <> 0;
    finally
      FindClose(SR);
    end;
  end;
  RemoveDir(Dir);
end;

function TFileSyncManager.CopyFileSafe(const Source, Dest: string): Boolean;
var
  SrcStream, DestStream: TFileStream;
begin
  Result := False;
  try
    SrcStream := TFileStream.Create(Source, fmOpenRead or fmShareDenyWrite);
    try
      DestStream := TFileStream.Create(Dest, fmCreate or fmShareExclusive);
      try
        DestStream.CopyFrom(SrcStream, 0);
        Result := True;
      finally
        DestStream.Free;
      end;
    finally
      SrcStream.Free;
    end;
  except
    on E: Exception do
      Writeln('   [Error Copying] ', Source, ' -> ', E.Message);
  end;
end;

function TFileSyncManager.FilesAreIdentical(const SrcFile, DestFile: string): Boolean;
var
  SrcRec, DestRec: TSearchRec;
  SrcTime, DestTime: TDateTime;
begin
  Result := False;
  if (FindFirst(SrcFile, faAnyFile, SrcRec) = 0) then
  begin
    try
      if (FindFirst(DestFile, faAnyFile, DestRec) = 0) then
      begin
        try
          if SrcRec.Size <> DestRec.Size then Exit;
          SrcTime := FileDateToDateTime(SrcRec.Time);
          DestTime := FileDateToDateTime(DestRec.Time);
          if Abs(SecondsBetween(SrcTime, DestTime)) > 2 then Exit;
          Result := True;
        finally
          FindClose(DestRec);
        end;
      end;
    finally
      FindClose(SrcRec);
    end;
  end;
end;

procedure TFileSyncManager.BuildMirrorPhase(const SrcRoot, DestRoot: string);
var
  SR: TSearchRec;
  SrcItem, DestItem: string;
begin
  if FindFirst(IncludeTrailingPathDelimiter(DestRoot) + '*', faAnyFile, SR) = 0 then
  begin
    try
      repeat
        if (SR.Name = '.') or (SR.Name = '..') then Continue;
        if IsExcluded(SR.Name) then Continue;
        
        SrcItem := IncludeTrailingPathDelimiter(SrcRoot) + SR.Name;
        DestItem := IncludeTrailingPathDelimiter(DestRoot) + SR.Name;

        if not FileExists(SrcItem) and not DirectoryExists(SrcItem) then
        begin
          AddOperation('', DestItem, saDelete, (SR.Attr and faDirectory) <> 0, 'Does not exist in source');
        end
        else if (SR.Attr and faDirectory) <> 0 then
        begin
          BuildMirrorPhase(SrcItem, DestItem);
        end;
      until FindNext(SR) <> 0;
    finally
      FindClose(SR);
    end;
  end;
end;

procedure TFileSyncManager.BuildSyncPhase(const SrcRoot, DestRoot: string);
var
  SR: TSearchRec;
  SrcItem, DestItem: string;
begin
  if FindFirst(IncludeTrailingPathDelimiter(SrcRoot) + '*', faAnyFile, SR) = 0 then
  begin
    try
      repeat
        if (SR.Name = '.') or (SR.Name = '..') then Continue;
        if IsExcluded(SR.Name) then Continue;
        
        SrcItem := IncludeTrailingPathDelimiter(SrcRoot) + SR.Name;
        DestItem := IncludeTrailingPathDelimiter(DestRoot) + SR.Name;

        if (SR.Attr and faDirectory) <> 0 then
        begin
          if not DirectoryExists(DestItem) then
            AddOperation(SrcItem, DestItem, saCopy, True, 'New directory');
          BuildSyncPhase(SrcItem, DestItem);
        end
        else
        begin
          if not FileExists(DestItem) then
            AddOperation(SrcItem, DestItem, saCopy, False, 'New file')
          else if not FilesAreIdentical(SrcItem, DestItem) then
            AddOperation(SrcItem, DestItem, saUpdate, False, 'File changed');
        end;
      until FindNext(SR) <> 0;
    finally
      FindClose(SR);
    end;
  end;
end;

procedure TFileSyncManager.BuildPipeline;
begin
  SetLength(FOperations, 0);
  if not DirectoryExists(FSourcePath) then
  begin
    WriteLn('Error: Source directory does not exist: ', FSourcePath);
    Exit;
  end;
  
  BuildMirrorPhase(FSourcePath, FDestPath);
  BuildSyncPhase(FSourcePath, FDestPath);
end;

procedure TFileSyncManager.PrintDryRun;
var
  i: Integer;
begin
  WriteLn('--- DRY RUN: File Sync Plan ---');
  WriteLn('Source: ', FSourcePath);
  WriteLn('Dest:   ', FDestPath);
  WriteLn('');
  
  if Length(FOperations) = 0 then
  begin
    WriteLn('No changes detected. Everything is in sync.');
    Exit;
  end;

  for i := 0 to High(FOperations) do
  begin
    case FOperations[i].Action of
      saCopy:   Write('[+] NEW    ');
      saUpdate: Write('[*] UPDATE ');
      saDelete: Write('[-] DELETE ');
    end;
    
    if FOperations[i].IsDirectory then Write('Dir:  ') else Write('File: ');
    
    if FOperations[i].Action = saDelete then
      WriteLn(FOperations[i].DestPath)
    else
      WriteLn(FOperations[i].SrcPath, ' -> ', FOperations[i].DestPath);
      
    WriteLn('    Reason: ', FOperations[i].Reason);
  end;
  WriteLn('');
  WriteLn('Total operations: ', Length(FOperations));
  WriteLn('-------------------------------');
end;

procedure TFileSyncManager.ExecutePipeline;
var
  i: Integer;
  Op: TSyncOperation;
begin
  if Length(FOperations) = 0 then Exit;

  WriteLn('Executing Sync Pipeline...');

  for i := 0 to High(FOperations) do
  begin
    Op := FOperations[i];
    case Op.Action of
      saDelete:
      begin
        FileSetAttr(Op.DestPath, 0);
        if Op.IsDirectory then
        begin
          if DeleteDirRec(Op.DestPath) then
            WriteLn('[-] Removed Dir:  ', Op.DestPath);
        end
        else
        begin
          if DeleteFile(Op.DestPath) then
            WriteLn('[-] Removed File: ', Op.DestPath);
        end;
      end;
      saCopy, saUpdate:
      begin
        if Op.IsDirectory then
        begin
          if ForceDirectories(Op.DestPath) then
            WriteLn('[+] Created Dir:  ', Op.DestPath);
        end
        else
        begin
          ForceDirectories(ExtractFilePath(Op.DestPath));
          if FileExists(Op.DestPath) then FileSetAttr(Op.DestPath, 0);
          if CopyFileSafe(Op.SrcPath, Op.DestPath) then
          begin
            FileSetDate(Op.DestPath, FileAge(Op.SrcPath));
            if Op.Action = saCopy then
              WriteLn('[+] Copied:       ', Op.DestPath)
            else
              WriteLn('[*] Updated:      ', Op.DestPath);
          end;
        end;
      end;
    end;
  end;
  WriteLn('Sync complete.');
end;

end.
