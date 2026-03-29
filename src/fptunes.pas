program fptunes;

{$mode objfpc}{$H+}

uses
  Classes, SysUtils, CustApp, uAudioNormalizer,
  fpjson, jsonparser, opensslsockets, uMusicProviderAPI, uMusicProviderUtils, uConfig, uLibraryManager;

const
  APP_VERSION = '0.5.1';

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
  // Load configuration 
  AppConfig := TAppConfig.Create(ExtractFilePath(ParamStr(0)) + 'fptunes.ini');
end;

destructor TFPTunesApp.Destroy;
begin
  if Assigned(AppConfig) then
    FreeAndNil(AppConfig);
  inherited Destroy;
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
    AppConfig.GenerateDefaults(ExtractFilePath(ParamStr(0)) + 'fptunes.ini');
    Exit;
  end;
  
  WriteLn('Current Configuration Path: ', ExtractFilePath(ParamStr(0)) + 'fptunes.ini');
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
    while not Eof(F) do begin ReadLn(F, Line); FileContent := FileContent + Line; end;
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
  InputFile: string;
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

  // Check if they want the two-pass algorithm 
  if HasOption('two-pass') then
  begin
    ConvertM4AToFlacTwoPass(InputFile);
  end
  else
  begin
    // Placeholder for future single-pass logic
    Writeln('Single-pass normalization is not yet implemented.');
    Writeln('Please use the --two-pass flag.');
  end;
end;

// ============================================================================
// HELP MENU
// ============================================================================
procedure TFPTunesApp.WriteHelp;
begin
  Writeln('fptunes version ', APP_VERSION, ' - The Free Pascal Audio Suite');
  Writeln('Usage: ', ExeName, ' [command] [options]');
  Writeln('');
  Writeln('Commands:');
  Writeln('  norm         Normalize audio loudness to EBU R128 (-14 LUFS)');
  Writeln('  manage       Process and route files into your library structure');
  Writeln('  config       Manage application configuration');
  Writeln('  convert      (Coming soon) Convert between audio formats');
  Writeln('');
  Writeln('Options for "norm":');
  Writeln('  -i, --input  <path>   The audio file to process');
  Writeln('  --two-pass            Use the studio-grade two-pass algorithm');
  Writeln('');
  Writeln('Options for "manage":');
  Writeln('  --convert             Convert .m4a files to FLAC (uses INI settings)');
  Writeln('  --true-peak           Bypass R128; use pure limit to preserve original loudness');
  Writeln('  --lufs       <val>    Override the TargetLUFS defined in INI (e.g., -9.0)');
  Writeln('  --move                Route files to quality-specific library folders');
  Writeln('  -i, --input  <path>   Override the InputPath defined in INI');
  Writeln('  --backup     <path>   Override the BackupM4APath defined in INI');
  Writeln('');
  Writeln('Options for "config":');
  Writeln('  --regenerate          Create or overwrite fptunes.ini with default values');
  Writeln('');
  Writeln('Global Options:');
  Writeln('  -v, --version         Show version information');
  Writeln('  -h, --help            Show this help menu');
  Writeln('');
  Writeln('Example:');
  Writeln('  fptunes manage --convert --true-peak --move');
end;

// ============================================================================
// MAIN APPLICATION ROUTER
// ============================================================================
procedure TFPTunesApp.DoRun;
var
  ErrorMsg: String;
  Command: String;
begin
  // Quick check parameters
  ErrorMsg := CheckOptions('hiv', 'help input: two-pass auth regenerate convert move backup: true-peak lufs: version');
  if ErrorMsg <> '' then begin
    ShowException(Exception.Create(ErrorMsg));
    Terminate;
    Exit;
  end;

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
