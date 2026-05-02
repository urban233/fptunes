program fptunes;

{$mode objfpc}{$H+}

uses
  Classes, SysUtils, CustApp, uAudioNormalizer,
  fpjson, jsonparser, opensslsockets, uMusicProviderAPI, uMusicProviderUtils, uConfig, uLibraryManager, uFileSync;

const
  APP_VERSION = '0.6.0';

type
  { TFPTunesApp }
  TFPTunesApp = class(TCustomApplication)
  protected
    procedure DoRun; override;
  private
    procedure WriteHelp;
    procedure WriteVersion;
    procedure HandleNormCommand;
    procedure HandleMusicProviderCommand;
    procedure HandleConfigCommand;
    procedure HandleManageCommand;
    procedure HandleFileSyncCommand;
    function FindConfigPath: string;
  public
    constructor Create(TheOwner: TComponent); override;
    destructor Destroy; override;
  end;

{ TFPTunesApp }

procedure TFPTunesApp.WriteVersion;
begin
  Writeln('fptunes version ', APP_VERSION);
end;

constructor TFPTunesApp.Create(TheOwner: TComponent);
begin
  inherited Create(TheOwner);
end;

function TFPTunesApp.FindConfigPath: string;
var
  CustomPath: string;
begin
  if HasOption('c', 'config') then
  begin
    CustomPath := GetOptionValue('c', 'config');
    if not FileExists(CustomPath) then
      WriteLn('Warning: Specified configuration file not found: ', CustomPath);
    Result := CustomPath;
    Exit;
  end;

  // 1. Check Current Working Directory
  Result := 'fptunes.ini';
  if FileExists(Result) then Exit;

  // 2. Fallback to Executable Directory
  Result := ExtractFilePath(ParamStr(0)) + 'fptunes.ini';
end;


destructor TFPTunesApp.Destroy;
begin
  if Assigned(AppConfig) then
    FreeAndNil(AppConfig);
  inherited Destroy;
end;

// ============================================================================
// COMMAND: filesync (One-Way Recursive Sync)
// ============================================================================
procedure TFPTunesApp.HandleFileSyncCommand;
var
  Manager: TFileSyncManager;
  UserResponse, Src, Dest: string;
begin
  if HasOption('v', 'version') then
  begin
    WriteVersion;
    Exit;
  end;

  Src := AppConfig.SyncSource;
  Dest := AppConfig.SyncDest;

  if HasOption('src') then
    Src := GetOptionValue('src');
  if HasOption('dest') then
    Dest := GetOptionValue('dest');

  if (Src = '') or (Dest = '') then
  begin
    WriteLn('Error: Source and Destination paths must be specified in INI or via flags.');
    Exit;
  end;

  Manager := TFileSyncManager.Create(Src, Dest);
  try
    Manager.BuildPipeline;
    Manager.PrintDryRun;

    Write('Proceed with synchronization? (y/N): ');
    ReadLn(UserResponse);
    if LowerCase(Trim(UserResponse)) = 'y' then
      Manager.ExecutePipeline
    else
      WriteLn('Operation cancelled by user.');
  finally
    Manager.Free;
  end;
end;

// ============================================================================
// COMMAND: manage (Library Management)
// ============================================================================
procedure TFPTunesApp.HandleManageCommand;
var
  Manager: TLibraryManager;
  DoConvert, DoMove, UseTruePeak: Boolean;
  UserResponse: string;
  FormatSettings: TFormatSettings;
begin
  if HasOption('v', 'version') then
  begin
    WriteVersion;
    Exit;
  end;

  DoConvert := HasOption('convert');
  DoMove := HasOption('move');
  UseTruePeak := HasOption('true-peak');

  if not DoConvert and not DoMove then
  begin
    WriteLn('Error: You must specify at least --convert or --move to manage files.');
    Exit;
  end;

  // Override config paths if provided via CLI
  if HasOption('i', 'input') then
    AppConfig.InputPath := GetOptionValue('i', 'input');
  if HasOption('backup') then
    AppConfig.BackupM4APath := GetOptionValue('backup');
    
  if HasOption('lufs') then
  begin
    FormatSettings := DefaultFormatSettings;
    FormatSettings.DecimalSeparator := '.';
    AppConfig.TargetLUFS := StrToFloatDef(GetOptionValue('lufs'), -14.0, FormatSettings);
  end;

  Manager := TLibraryManager.Create(DoConvert, UseTruePeak, DoMove);
  try
    Manager.BuildPipeline;
    Manager.PrintDryRun;

    Write('Proceed with execution? (y/N): ');
    ReadLn(UserResponse);
    if LowerCase(Trim(UserResponse)) = 'y' then
      Manager.ExecutePipeline
    else
      WriteLn('Operation cancelled by user.');
  finally
    Manager.Free;
  end;
end;

// ============================================================================
// COMMAND: config (Configuration Management)
// ============================================================================
procedure TFPTunesApp.HandleConfigCommand;
begin
  if HasOption('v', 'version') then
  begin
    WriteVersion;
    Exit;
  end;

  if HasOption('regenerate') then
  begin
    AppConfig.GenerateDefaults(AppConfig.LoadedPath);
    Exit;
  end;
  
  WriteLn('Current Configuration Path: ', AppConfig.LoadedPath);
  WriteLn('Use "fptunes config --regenerate" to overwrite with default values.');
end;

// ============================================================================
// COMMAND: xsync (Hidden Music Provider Access)
// ============================================================================
procedure TFPTunesApp.HandleMusicProviderCommand;
var
  MusicProvider: TMusicProviderAPI;
  UrlList: TStringList;
  FileContent, Line, MediaType, InputFile, CurrentUrl: string;
  F: TextFile;
  i: Integer;
  Metadata: TJSONObject;
begin
  if HasOption('v', 'version') then
  begin
    WriteVersion;
    Exit;
  end;

  Randomize;
  MusicProvider := TMusicProviderAPI.Create;
  
  if HasOption('auth') then
  begin
    try
      if MusicProvider.Login then
        WriteLn('Authentication successful. Token saved.');
    finally
      MusicProvider.Free;
    end;
    Exit;
  end;

  if HasOption('i', 'input') then
    InputFile := GetOptionValue('i', 'input')
  else
  begin
    Writeln('Error: Input file required.');
    MusicProvider.Free;
    Exit;
  end;

  UrlList := TStringList.Create;
  try
    if not MusicProvider.Login then Exit;
    if not FileExists(InputFile) then begin WriteLn('File not found.'); Exit; end;

    AssignFile(F, InputFile); Reset(F); FileContent := '';
    while not Eof(F) do
    begin
      ReadLn(F, Line);
      Line := Trim(Line);
      if (Line <> '') and (Line[1] <> '#') then
        FileContent := FileContent + Line;
    end;
    CloseFile(F);

    UrlList.Delimiter := ';';
    UrlList.StrictDelimiter := True;
    UrlList.DelimitedText := FileContent;

    for i := 0 to UrlList.Count - 1 do begin
      CurrentUrl := Trim(UrlList.Strings[i]);
      if CurrentUrl = '' then Continue;
      
      MediaType := DetectMediaType(CurrentUrl);
      WriteLn(Format('[%d/%d] Processing %s...', [i + 1, UrlList.Count, CurrentUrl]));
      
      MusicProvider.DownloadMedia(MediaType, CurrentUrl);
    end;
  finally
    MusicProvider.Free;
    UrlList.Free;
    WriteLn(''); WriteLn('Sync complete.');
  end;
end;

// ============================================================================
// COMMAND: norm (Loudness Normalization)
// ============================================================================
procedure TFPTunesApp.HandleNormCommand;
var
  InputFile, OutputFile, DestFile: string;
  UseTruePeak, UseTwoPass, Success: Boolean;
  FormatSettings: TFormatSettings;
begin
  if HasOption('v', 'version') then
  begin
    WriteVersion;
    Exit;
  end;

  // Check if the user provided an input file using -i or --input
  if HasOption('i', 'input') then
    InputFile := GetOptionValue('i', 'input')
  else
  begin
    Writeln('Error: You must specify an input file.');
    Writeln('Usage: fptunes norm -i <file_path>');
    Exit;
  end;

  // Validate the file exists
  if not FileExists(InputFile) then
  begin
    Writeln('Error: Cannot find the file: ', InputFile);
    Exit;
  end;

  UseTruePeak := HasOption('true-peak');
  UseTwoPass := HasOption('two-pass');
  
  if HasOption('lufs') then
  begin
    FormatSettings := DefaultFormatSettings;
    FormatSettings.DecimalSeparator := '.';
    AppConfig.TargetLUFS := StrToFloatDef(GetOptionValue('lufs'), -14.0, FormatSettings);
  end;

  if not UseTruePeak and not UseTwoPass then
  begin
    Writeln('Error: You must specify --two-pass or --true-peak.');
    Exit;
  end;

  if HasOption('dest') then
  begin
    DestFile := GetOptionValue('dest');
    // If dest is a directory, append filename
    if DirectoryExists(DestFile) or (DestFile[Length(DestFile)] = PathDelim) then
    begin
      ForceDirectories(DestFile);
      DestFile := IncludeTrailingPathDelimiter(DestFile) + ChangeFileExt(ExtractFileName(InputFile), '.' + AppConfig.OutputCodec);
    end;
    OutputFile := DestFile;
  end
  else
  begin
    // In-place logic
    OutputFile := ChangeFileExt(InputFile, '.' + AppConfig.OutputCodec);
    // If same extension, use temp file to avoid ffmpeg reading/writing same file
    if LowerCase(ExtractFileExt(InputFile)) = LowerCase(ExtractFileExt(OutputFile)) then
      OutputFile := InputFile + '.tmp';
  end;

  Success := False;
  if UseTwoPass then
    Success := ConvertM4AToFlacTwoPass(InputFile, OutputFile)
  else if UseTruePeak then
    Success := ConvertM4AToFlacTruePeak(InputFile, OutputFile);

  if Success then
  begin
    if not HasOption('dest') then
    begin
      // Handle in-place finalization
      if LowerCase(ExtractFileExt(InputFile)) = LowerCase(ExtractFileExt(OutputFile)) then
      begin
        if not RenameFile(OutputFile, InputFile) then
          Writeln('  -> Error: Failed to replace original file with normalized version.')
        else
          Writeln('  -> Done (In-Place).');
      end
      else
      begin
        // Format changed, remove original if requested (in-place default)
        if FileExists(InputFile) then DeleteFile(InputFile);
        Writeln('  -> Done (In-Place, format changed). New file: ', OutputFile);
      end;
    end
    else
      Writeln('  -> Done. File saved to: ', OutputFile);
  end;
end;

// ============================================================================
// HELP MENU
// ============================================================================
procedure TFPTunesApp.WriteHelp;
begin
  Writeln('fptunes version ', APP_VERSION, ' - The Free Pascal Audio Manager');
  Writeln('Usage: ', ExeName, ' [command] [options]');
  Writeln('');
  Writeln('Commands:');
  Writeln('  filesync     One-way recursive sync between two folders');
  Writeln('  manage       Process and route files into your library structure');
  Writeln('  norm         Normalize audio loudness to EBU R128 (-14 LUFS)');
  Writeln('  config       Manage application configuration');
  Writeln('');
  Writeln('Options for "filesync":');
  Writeln('  --src        <path>   Source directory (overrides INI)');
  Writeln('  --dest       <path>   Destination directory (overrides INI)');
  Writeln('');
  Writeln('Options for "manage":');
  Writeln('  --convert             Convert .m4a files to FLAC (uses INI settings)');
  Writeln('  --true-peak           Bypass R128; use pure limit to preserve original loudness');
  Writeln('  --lufs       <val>    Override the TargetLUFS defined in INI (e.g., -9.0)');
  Writeln('  --move                Route files to quality-specific library folders');
  Writeln('  -i, --input  <path>   Override the InputPath defined in INI');
  Writeln('  --backup     <path>   Override the BackupM4APath defined in INI');
  Writeln('');
  Writeln('Options for "norm":');
  Writeln('  -i, --input  <path>   The audio file to process');
  Writeln('  --two-pass            Use the studio-grade two-pass algorithm');
  Writeln('  --true-peak           Use pure limit to preserve original loudness');
  Writeln('  --lufs       <val>    Override the TargetLUFS defined in INI (e.g., -14.0)');
  Writeln('  --dest       <path>   Save normalized file to this path (default: in-place)');
  Writeln('');
  Writeln('Options for "config":');
  Writeln('  --regenerate          Create or overwrite fptunes.ini with default values');
  Writeln('');
  Writeln('Global Options:');
  Writeln('  -v, --version         Show version information');
  Writeln('  -h, --help            Show this help menu');
  Writeln('  -c, --config <path>   Use a specific .ini configuration file');
  Writeln('');
  Writeln('Example:');
  Writeln('  fptunes manage --convert --true-peak --move');
  Writeln('  fptunes norm -i input.m4a --two-pass --dest ./normalized/');
end;

// ============================================================================
// MAIN APPLICATION ROUTER
// ============================================================================
procedure TFPTunesApp.DoRun;
var
  ErrorMsg: String;
  Command: String;
  ConfigPath: string;
begin
  // Quick check parameters
  ErrorMsg := CheckOptions('hivc:', 'help input: two-pass auth regenerate convert move backup: true-peak lufs: dest: version src: config:');
  if ErrorMsg <> '' then begin
    ShowException(Exception.Create(ErrorMsg));
    Terminate;
    Exit;
  end;

  // Load configuration 
  ConfigPath := FindConfigPath;
  AppConfig := TAppConfig.Create(ConfigPath);

  // Parse Version
  if HasOption('v', 'version') then begin
    WriteVersion;
    Terminate;
    Exit;
  end;

  // Parse Help
  if HasOption('h', 'help') or (ParamCount = 0) then begin
    WriteHelp;
    Terminate;
    Exit;
  end;

  // Get the main subcommand (e.g., 'norm', 'convert')
  Command := ParamStr(1);

  // Route to the correct handler
  if Command = 'norm' then
    HandleNormCommand
  else if Command = 'manage' then
    HandleManageCommand
  else if Command = 'filesync' then
    HandleFileSyncCommand
  else if Command = 'xsync' then
    HandleMusicProviderCommand
  else if Command = 'config' then
    HandleConfigCommand
  else
  begin
    Writeln('Error: Unknown command "', Command, '"');
    WriteHelp;
  end;

  // Stop program loop
  Terminate;
end;

// ============================================================================
// PROGRAM ENTRY
// ============================================================================
var
  Application: TFPTunesApp;
begin
  Application := TFPTunesApp.Create(nil);
  Application.Title := 'fptunes';
  Application.Run;
  Application.Free;
end.
