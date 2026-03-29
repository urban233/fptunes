unit uMusicProviderUtils;

{
  MusicProvider Utility Functions
  Shared helpers for string manipulation and timing.
}
{$mode objfpc}{$H+}

interface

uses SysUtils, Classes, Math, uMusicProviderConstants;

{ Extracts a raw MusicProvider ID from either a numeric string or a full MusicProvider URL }
function ExtractIdFromUrl(const URLOrId: string): string;

{ Detects the media type (track, album, artist, etc.) from a URL }
function DetectMediaType(const URLOrId: string): string;

{ Pauses execution for a random duration to mimic human browsing behavior }
procedure RandomHumanSleep(MinMs, MaxMs: Integer);

implementation

function DetectMediaType(const URLOrId: string): string;
var
  Segments: TStringList;
  I: Integer;
  Segment: string;
begin
  Result := 'track'; // Default fallback
  if Pos(PROVIDER_DOMAIN, URLOrId) = 0 then Exit;
  
  Segments := TStringList.Create;
  try
    Segments.Delimiter := '/';
    Segments.StrictDelimiter := True;
    Segments.DelimitedText := URLOrId;
    for I := 0 to Segments.Count - 1 do
    begin
      Segment := LowerCase(Segments[I]);
      if (Segment = 'track') or (Segment = 'album') or 
         (Segment = 'artist') or (Segment = 'playlist') or (Segment = 'video') then
      begin
        Result := Segment;
        Break;
      end;
    end;
  finally
    Segments.Free;
  end;
end;

function ExtractIdFromUrl(const URLOrId: string): string;
var
  Segments: TStringList;
  I: Integer;
  Segment: string;
begin
  if Pos(PROVIDER_DOMAIN, URLOrId) = 0 then Exit(URLOrId);
  Segments := TStringList.Create;
  try
    Segments.Delimiter := '/';
    Segments.StrictDelimiter := True;
    Segments.DelimitedText := URLOrId;
    Result := '';
    for I := 0 to Segments.Count - 2 do
    begin
      Segment := LowerCase(Segments[I]);
      if (Segment = 'track') or (Segment = 'album') or 
         (Segment = 'artist') or (Segment = 'playlist') or (Segment = 'video') then
      begin
        Result := Segments[I + 1].Split(['?'])[0];
        Break;
      end;
    end;
    if Result = '' then 
      Result := Segments[Segments.Count - 1].Split(['?'])[0];
  finally
    Segments.Free;
  end;
end;

procedure RandomHumanSleep(MinMs, MaxMs: Integer);
var DelayMs: Integer;
begin
  DelayMs := RandomRange(MinMs, MaxMs);
  WriteLn(Format('Human delay: %d ms...', [DelayMs]));
  Sleep(DelayMs);
end;

end.

