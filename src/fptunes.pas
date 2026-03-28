program fptunes;

{$mode objfpc}{$H+}

uses
  Classes, SysUtils, CustApp, uAudioNormalizer;

type
  { TFPTunesApp }
  TFPTunesApp = class(TCustomApplication)
  protected
    procedure DoRun; override;
  private
    procedure WriteHelp;
    procedure HandleNormCommand;
  end;

{ TFPTunesApp }

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
  ErrorMsg := CheckOptions('hi:', 'help input: two-pass');
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
