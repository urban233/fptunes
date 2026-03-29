unit uMusicProviderAPI;

{
  MusicProvider API Client
  Specific implementations for media metadata retrieval and downloading.
}
{$mode objfpc}{$H+}

interface

uses SysUtils, Classes, fpjson, jsonparser, jsonscanner, fphttpclient, base64, uMusicProviderAuth, uMusicProviderConstants, uMusicProviderUtils;

type
  TMusicProviderAPI = class(TMusicProviderAuth)
  private
    procedure DownloadTrack(const TrackId, TrackTitle: string);
  public
    { Fetches metadata for a specific media item. Returns TJSONObject (must be freed by caller). }
    function FetchMediaMetadata(const MediaType: string; const URLOrId: string): TJSONObject;
    { Downloads a track or all tracks in an album }
    procedure DownloadMedia(const MediaType: string; const URLOrId: string);
  end;

implementation

function TMusicProviderAPI.FetchMediaMetadata(const MediaType: string; const URLOrId: string): TJSONObject;
var
  Id, Response, RequestUrl: string;
  Parser: TJSONParser;
begin
  Result := nil;
  Id := ExtractIdFromUrl(URLOrId);
  RandomHumanSleep(3000, 5000);

  RequestUrl := Format('%s%ss/%s?countryCode=%s', [URL_API_BASE, MediaType, Id, COUNTRY_CODE]);

  try
    Response := FHttpClient.Get(RequestUrl);
    Parser := TJSONParser.Create(Response, [joUTF8]);
    try Result := Parser.Parse as TJSONObject; finally Parser.Free; end;
  except
    on E: Exception do WriteLn(Format('Error fetching %s [%s]: %s', [MediaType, Id, E.Message]));
  end;
end;

procedure TMusicProviderAPI.DownloadTrack(const TrackId, TrackTitle: string);
var
  Response, ManifestB64, ManifestJsonStr, StreamUrl, FileExt, SafeTitle: string;
  PlaybackInfo, ManifestData: TJSONObject;
  Parser: TJSONParser;
  UrlsArray: TJSONArray;
  FS: TFileStream;
  DownloadClient: TFPHTTPClient;
  i: Integer;
begin
  RandomHumanSleep(1000, 2000);
  WriteLn('  [+] Requesting stream manifest for track: ', TrackTitle);
  
  // Create a safe filename
  SafeTitle := TrackTitle;
  for i := 1 to Length(SafeTitle) do
    if SafeTitle[i] in ['\', '/', ':', '*', '?', '"', '<', '>', '|'] then
      SafeTitle[i] := '_';

  try
    Response := FHttpClient.Get(Format('%stracks/%s/playbackinfopostpaywall?playbackmode=STREAM&audioquality=HIGH&assetpresentation=FULL&countryCode=%s', [URL_API_BASE, TrackId, COUNTRY_CODE]));
    Parser := TJSONParser.Create(Response, [joUTF8]);
    try
      PlaybackInfo := Parser.Parse as TJSONObject;
      try
        if PlaybackInfo.Find('manifest') = nil then begin
          WriteLn('  [!] Track stream not available or requires higher subscription.');
          Exit;
        end;
        ManifestB64 := PlaybackInfo.Strings['manifest'];
        ManifestJsonStr := DecodeStringBase64(ManifestB64);
      finally PlaybackInfo.Free; end;
    finally Parser.Free; end;

    Parser := TJSONParser.Create(ManifestJsonStr, [joUTF8]);
    try
      ManifestData := Parser.Parse as TJSONObject;
      try
        UrlsArray := ManifestData.Arrays['urls'];
        if (UrlsArray <> nil) and (UrlsArray.Count > 0) then
          StreamUrl := UrlsArray.Strings[0]
        else
        begin
          WriteLn('  [!] No stream URL found in manifest.');
          Exit;
        end;
        
        if Pos('audio/mp4', ManifestData.Strings['mimeType']) > 0 then FileExt := '.m4a'
        else if Pos('flac', ManifestData.Strings['mimeType']) > 0 then FileExt := '.flac'
        else FileExt := '.ts';
      finally ManifestData.Free; end;
    finally Parser.Free; end;

    WriteLn('  [+] Downloading stream...');
    FS := TFileStream.Create(SafeTitle + FileExt, fmCreate);
    try
      DownloadClient := TFPHTTPClient.Create(nil);
      try
        DownloadClient.Get(StreamUrl, FS);
      finally DownloadClient.Free; end;
    finally FS.Free; end;
    WriteLn('  [+] Saved as ', SafeTitle, FileExt);
  except
    on E: Exception do WriteLn('  [!] Error downloading track: ', E.Message);
  end;
end;

procedure TMusicProviderAPI.DownloadMedia(const MediaType: string; const URLOrId: string);
var
  Id, Response, TrackId, TrackTitle: string;
  Metadata, TrackObj: TJSONObject;
  ItemsArray: TJSONArray;
  Parser: TJSONParser;
  i: Integer;
begin
  Id := ExtractIdFromUrl(URLOrId);
  
  if MediaType = 'track' then
  begin
    Metadata := FetchMediaMetadata(MediaType, Id);
    if Assigned(Metadata) then
    begin
      try
        DownloadTrack(Id, Metadata.Strings['title']);
      finally Metadata.Free; end;
    end;
  end
  else if MediaType = 'album' then
  begin
    WriteLn('Fetching album tracks...');
    try
      Response := FHttpClient.Get(Format('%salbums/%s/tracks?countryCode=%s&limit=1000', [URL_API_BASE, Id, COUNTRY_CODE]));
      Parser := TJSONParser.Create(Response, [joUTF8]);
      try
        Metadata := Parser.Parse as TJSONObject;
        try
          ItemsArray := Metadata.Arrays['items'];
          if Assigned(ItemsArray) then
          begin
            WriteLn(Format('Found %d tracks in album.', [ItemsArray.Count]));
            for i := 0 to ItemsArray.Count - 1 do
            begin
              TrackObj := ItemsArray.Objects[i];
              TrackId := IntToStr(TrackObj.Integers['id']);
              TrackTitle := TrackObj.Strings['title'];
              WriteLn(Format('Downloading track %d/%d...', [i+1, ItemsArray.Count]));
              DownloadTrack(TrackId, TrackTitle);
            end;
          end;
        finally Metadata.Free; end;
      finally Parser.Free; end;
    except
      on E: Exception do WriteLn('Error fetching album tracks: ', E.Message);
    end;
  end
  else
  begin
    WriteLn('Download for media type "', MediaType, '" is not supported yet.');
  end;
end;

end.

