program fptunes;

{$mode objfpc}{$H+}

uses
  Classes, SysUtils, CustApp, uAudioNormalizer,
  fpjson, jsonparser, opensslsockets, uMusicProviderAPI, uMusicProviderUtils;

type
  { TFPTunesApp }
  TFPTunesApp = class(TCustomApplication)
  protected
    procedure DoRun; override;
  private
    procedure WriteHelp;
    procedure HandleNormCommand;
    procedure HandleMusicProviderCommand;
  end;

{ TFPTunesApp }

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
  Writeln('fptunes - The Free Pascal Audio Suite');
  Writeln('Usage: ', ExeName, ' [command] [options]');
  Writeln('');
  Writeln('Commands:');
  Writeln('  norm         Normalize audio loudness to EBU R128 (-14 LUFS)');
  Writeln('  convert      (Coming soon) Convert between audio formats');
  Writeln('');
  Writeln('Options for "norm":');
  Writeln('  -i, --input  <path>   The audio file to process');
  Writeln('  --two-pass            Use the studio-grade two-pass algorithm');
  Writeln('  -h, --help            Show this help menu');
  Writeln('');
  Writeln('Example:');
  Writeln('  fptunes norm -i song.m4a --two-pass');
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
  ErrorMsg := CheckOptions('hi:', 'help input: two-pass auth');
  if ErrorMsg <> '' then begin
    ShowException(Exception.Create(ErrorMsg));
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
  else if Command = 'xsync' then
    HandleMusicProviderCommand
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
