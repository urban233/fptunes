unit uConfig;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, IniFiles;

type
  { TAppConfig }
  TAppConfig = class
  private
    FIniFile: TIniFile;
    // Conversion Settings
    FFFMpegPath: string;
    FTargetLUFS: Double;
    FTargetLRA: Double;
    FTargetTP: Double;
    FOutputCodec: string;
    FSampleFormat: string;
    FSampleRate: Integer;
    FCompressionLevel: Integer;
    
    FPaths: array[0..7] of string;
    function GetStrProp(Index: Integer): string;
    procedure SetStrProp(Index: Integer; const Value: string);

    procedure LoadDefaults;
  public
    constructor Create(const ConfigPath: string);
    destructor Destroy; override;

    procedure GenerateDefaults(const ConfigPath: string);

    property FFMpegPath: string read FFFMpegPath write FFFMpegPath;
    property TargetLUFS: Double read FTargetLUFS write FTargetLUFS;
    property TargetLRA: Double read FTargetLRA write FTargetLRA;
    property TargetTP: Double read FTargetTP write FTargetTP;
    property OutputCodec: string read FOutputCodec write FOutputCodec;
    property SampleFormat: string read FSampleFormat write FSampleFormat;
    property SampleRate: Integer read FSampleRate write FSampleRate;
    property CompressionLevel: Integer read FCompressionLevel write FCompressionLevel;

    // Management Settings
    property InputPath: string index 0 read GetStrProp write SetStrProp;
    property HiResPath: string index 1 read GetStrProp write SetStrProp;
    property CDQualityPath: string index 2 read GetStrProp write SetStrProp;
    property WavPath: string index 3 read GetStrProp write SetStrProp;
    property Mp3Path: string index 4 read GetStrProp write SetStrProp;
    property BackupM4APath: string index 5 read GetStrProp write SetStrProp;
    
    // Sync Settings
    property SyncSource: string index 6 read GetStrProp write SetStrProp;
    property SyncDest: string index 7 read GetStrProp write SetStrProp;
  end;

var
  AppConfig: TAppConfig;

implementation

function TAppConfig.GetStrProp(Index: Integer): string;
begin
  Result := FPaths[Index];
end;

procedure TAppConfig.SetStrProp(Index: Integer; const Value: string);
begin
  FPaths[Index] := Value;
end;

constructor TAppConfig.Create(const ConfigPath: string);
var
  FormatSettings: TFormatSettings;
begin
  FIniFile := TIniFile.Create(ConfigPath);
  
  // Ensure dots are used for floats in INI files regardless of system locale
  FormatSettings := DefaultFormatSettings;
  FormatSettings.DecimalSeparator := '.';

  // Load Conversion Settings
  FFFMpegPath := FIniFile.ReadString('Conversion', 'FFMpegPath', 'ffmpeg');
  FTargetLUFS := StrToFloatDef(FIniFile.ReadString('Conversion', 'TargetLUFS', '-14.0'), -14.0, FormatSettings);
  FTargetLRA := StrToFloatDef(FIniFile.ReadString('Conversion', 'TargetLRA', '11.0'), 11.0, FormatSettings);
  FTargetTP := StrToFloatDef(FIniFile.ReadString('Conversion', 'TargetTP', '-1.0'), -1.0, FormatSettings);
  
  FOutputCodec := FIniFile.ReadString('Conversion', 'OutputCodec', 'flac');
  FSampleFormat := FIniFile.ReadString('Conversion', 'SampleFormat', 's32');
  FSampleRate := FIniFile.ReadInteger('Conversion', 'SampleRate', 44100);
  FCompressionLevel := FIniFile.ReadInteger('Conversion', 'CompressionLevel', 8);

  // Load Management Settings
  FPaths[0] := FIniFile.ReadString('Management', 'InputPath', './input');
  FPaths[1] := FIniFile.ReadString('Management', 'HiResPath', './library/hires');
  FPaths[2] := FIniFile.ReadString('Management', 'CDQualityPath', './library/cdquality');
  FPaths[3] := FIniFile.ReadString('Management', 'WavPath', './library/wav');
  FPaths[4] := FIniFile.ReadString('Management', 'Mp3Path', './library/mp3');
  FPaths[5] := FIniFile.ReadString('Management', 'BackupM4APath', './backup/m4a');
  
  // Load Sync Settings
  FPaths[6] := FIniFile.ReadString('Sync', 'SourcePath', './sync_src');
  FPaths[7] := FIniFile.ReadString('Sync', 'DestPath', './sync_dest');
end;

procedure TAppConfig.GenerateDefaults(const ConfigPath: string);
var
  FormatSettings: TFormatSettings;
begin
  FormatSettings := DefaultFormatSettings;
  FormatSettings.DecimalSeparator := '.';

  FIniFile.WriteString('Conversion', 'FFMpegPath', 'ffmpeg');
  FIniFile.WriteString('Conversion', 'TargetLUFS', FloatToStr(-14.0, FormatSettings));
  FIniFile.WriteString('Conversion', 'TargetLRA', FloatToStr(11.0, FormatSettings));
  FIniFile.WriteString('Conversion', 'TargetTP', FloatToStr(-1.0, FormatSettings));
  FIniFile.WriteString('Conversion', 'OutputCodec', 'flac');
  FIniFile.WriteString('Conversion', 'SampleFormat', 's32');
  FIniFile.WriteInteger('Conversion', 'SampleRate', 44100);
  FIniFile.WriteInteger('Conversion', 'CompressionLevel', 8);

  FIniFile.WriteString('Management', 'InputPath', './input');
  FIniFile.WriteString('Management', 'HiResPath', './library/hires');
  FIniFile.WriteString('Management', 'CDQualityPath', './library/cdquality');
  FIniFile.WriteString('Management', 'WavPath', './library/wav');
  FIniFile.WriteString('Management', 'Mp3Path', './library/mp3');
  FIniFile.WriteString('Management', 'BackupM4APath', './backup/m4a');
  
  FIniFile.WriteString('Sync', 'SourcePath', './sync_src');
  FIniFile.WriteString('Sync', 'DestPath', './sync_dest');

  FIniFile.UpdateFile;
  
  WriteLn('Configuration file generated at: ', ConfigPath);
end;

procedure TAppConfig.LoadDefaults;
begin
  // Handled in Create
end;

destructor TAppConfig.Destroy;
begin
  FIniFile.Free;
  inherited Destroy;
end;

initialization
  AppConfig := nil;

finalization
  if Assigned(AppConfig) then
    AppConfig.Free;

end.
