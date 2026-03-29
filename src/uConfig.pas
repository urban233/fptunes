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
  end;

var
  AppConfig: TAppConfig;

implementation

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
  FSampleFormat := FIniFile.ReadString('Conversion', 'SampleFormat', 's24');
  FSampleRate := FIniFile.ReadInteger('Conversion', 'SampleRate', 44100);
  FCompressionLevel := FIniFile.ReadInteger('Conversion', 'CompressionLevel', 8);
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
  FIniFile.WriteString('Conversion', 'SampleFormat', 's24');
  FIniFile.WriteInteger('Conversion', 'SampleRate', 44100);
  FIniFile.WriteInteger('Conversion', 'CompressionLevel', 8);
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
