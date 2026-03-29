program MusicProviderInterfaceApp;

{
  MusicProvider Metadata Fetcher
  Main CLI entry point. Reads a JSON file of IDs/URLs and prints metadata.
}
{$mode objfpc}{$H+}

uses SysUtils, Classes, fpjson, jsonparser, jsonscanner, opensslsockets, uMusicProviderAPI, uMusicProviderUtils;

var
  MusicProvider: TMusicProviderAPI;
  JsonInput: TJSONObject = nil;
  IdList: TJSONArray;
  Parser: TJSONParser = nil;
  FileContent, Line, MediaType: string;
  F: TextFile;
  i, j: Integer;
  Metadata: TJSONObject;

begin
  if ParamCount < 1 then begin
    WriteLn('Usage: MusicProviderInterfaceApp <input.json>');
    Exit;
  end;

  Randomize;
  MusicProvider := TMusicProviderAPI.Create;
  try
    if not MusicProvider.Login then Exit;

    if not FileExists(ParamStr(1)) then begin WriteLn('Input file not found.'); Exit; end;

    AssignFile(F, ParamStr(1)); Reset(F); FileContent := '';
    while not Eof(F) do begin ReadLn(F, Line); FileContent := FileContent + Line; end;
    CloseFile(F);

    Parser := TJSONParser.Create(FileContent, [joUTF8]);
    JsonInput := Parser.Parse as TJSONObject;

    for i := 0 to JsonInput.Count - 1 do begin
      MediaType := JsonInput.Names[i];
      IdList := JsonInput.Arrays[MediaType];
      WriteLn('');
      WriteLn('--- ' + UpperCase(MediaType) + 'S ---');
      for j := 0 to IdList.Count - 1 do begin
        Metadata := MusicProvider.FetchMediaMetadata(MediaType, IdList.Strings[j]);
        if Assigned(Metadata) then begin
          try
            if MediaType = 'artist' then WriteLn(' * ' + Metadata.Strings['name'])
            else WriteLn(' * ' + Metadata.Strings['title']);
          finally Metadata.Free; end;
        end;
      end;
    end;

  finally
    MusicProvider.Free;
    if Assigned(JsonInput) then JsonInput.Free;
    if Assigned(Parser) then Parser.Free;
    WriteLn(''); WriteLn('Processing complete.');
  end;
end.

