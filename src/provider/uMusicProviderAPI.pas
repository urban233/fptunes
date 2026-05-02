unit uMusicProviderAPI;

{
  MusicProvider API Client
  Specific implementations for media metadata retrieval and downloading.
}
{$mode objfpc}{$H+}

interface

uses SysUtils, Classes, fpjson, jsonparser, jsonscanner, fphttpclient, base64, uMusicProviderAuth, uMusicProviderConstants, uMusicProviderUtils, uConfig, Process;

type
  TMetaData = record
    Title: string;
    Artist: string;
    Album: string;
    TrackNumber: Integer;
    DiscNumber: Integer;
    ReleaseDate: string;
    ISRC: string;
    UPC: string;
    Copyright: string;
    Comment: string;
    CoverUUID: string;
  end;

  TMusicProviderAPI = class(TMusicProviderAuth)
  private
    procedure DownloadTrack(const TrackId: string; const Meta: TMetaData; const TargetFolder: string);
    procedure TagFile(const FilePath: string; const Meta: TMetaData);
    function GetCoverUrl(const UUID: string): string;
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

function TMusicProviderAPI.GetCoverUrl(const UUID: string): string;
begin
  if UUID = '' then Exit('');
  Result := 'https://resources.tidal.com/images/' + StringReplace(UUID, '-', '/', [rfReplaceAll]) + '/1280x1280.jpg';
end;

procedure TMusicProviderAPI.TagFile(const FilePath: string; const Meta: TMetaData);
var
  Proc: TProcess;
  TempPath, CoverPath: string;
  FS: TFileStream;
  DownloadClient: TFPHTTPClient;
begin
  CoverPath := '';
  if Meta.CoverUUID <> '' then
  begin
    CoverPath := FilePath + '.jpg';
    try
      DownloadClient := TFPHTTPClient.Create(nil);
      FS := TFileStream.Create(CoverPath, fmCreate);
      try
        DownloadClient.Get(GetCoverUrl(Meta.CoverUUID), FS);
      finally
        FS.Free;
        DownloadClient.Free;
      end;
    except
      CoverPath := ''; // Ignore cover if download fails
    end;
  end;

  TempPath := FilePath + '.tmp_tag';
  if not RenameFile(FilePath, TempPath) then Exit;

  Proc := TProcess.Create(nil);
  try
    Proc.Executable := AppConfig.FFMpegPath;
    Proc.Parameters.Add('-hide_banner');
    Proc.Parameters.Add('-y');
    Proc.Parameters.Add('-i');
    Proc.Parameters.Add(TempPath);
    
    if CoverPath <> '' then
    begin
      Proc.Parameters.Add('-i');
      Proc.Parameters.Add(CoverPath);
    end;

    Proc.Parameters.Add('-metadata');
    Proc.Parameters.Add('title=' + Meta.Title);
    Proc.Parameters.Add('-metadata');
    Proc.Parameters.Add('artist=' + Meta.Artist);
    Proc.Parameters.Add('-metadata');
    Proc.Parameters.Add('album=' + Meta.Album);
    Proc.Parameters.Add('-metadata');
    Proc.Parameters.Add('track=' + IntToStr(Meta.TrackNumber));
    Proc.Parameters.Add('-metadata');
    Proc.Parameters.Add('disc=' + IntToStr(Meta.DiscNumber));
    if Meta.ReleaseDate <> '' then
    begin
      Proc.Parameters.Add('-metadata');
      Proc.Parameters.Add('date=' + Meta.ReleaseDate);
    end;
    if Meta.ISRC <> '' then
    begin
      Proc.Parameters.Add('-metadata');
      Proc.Parameters.Add('isrc=' + Meta.ISRC);
    end;
    if Meta.UPC <> '' then
    begin
      Proc.Parameters.Add('-metadata');
      Proc.Parameters.Add('upc=' + Meta.UPC);
    end;
    if Meta.Copyright <> '' then
    begin
      Proc.Parameters.Add('-metadata');
      Proc.Parameters.Add('copyright=' + Meta.Copyright);
    end;
    if Meta.Comment <> '' then
    begin
      Proc.Parameters.Add('-metadata');
      Proc.Parameters.Add('comment=' + Meta.Comment);
    end;

    if CoverPath <> '' then
    begin
      Proc.Parameters.Add('-map');
      Proc.Parameters.Add('0:0');
      Proc.Parameters.Add('-map');
      Proc.Parameters.Add('1:0');
      Proc.Parameters.Add('-disposition:v');
      Proc.Parameters.Add('attached_pic');
    end;

    Proc.Parameters.Add('-c');
    Proc.Parameters.Add('copy');
    Proc.Parameters.Add(FilePath);

    Proc.Options := [poWaitOnExit];
    Proc.Execute;
    
    if Proc.ExitStatus = 0 then
      DeleteFile(TempPath)
    else
      RenameFile(TempPath, FilePath); // Rollback on error
  finally
    if (CoverPath <> '') and FileExists(CoverPath) then DeleteFile(CoverPath);
    Proc.Free;
  end;
end;

procedure TMusicProviderAPI.DownloadTrack(const TrackId: string; const Meta: TMetaData; const TargetFolder: string);
var
  Response, ManifestB64, ManifestJsonStr, StreamUrl, FileExt, SafeTitle, OutputPath: string;
  PlaybackInfo, ManifestData: TJSONObject;
  Parser: TJSONParser;
  UrlsArray: TJSONArray;
  FS: TFileStream;
  DownloadClient: TFPHTTPClient;
  i: Integer;
begin
  RandomHumanSleep(1000, 2000);
  WriteLn('  [+] Requesting stream manifest for track: ', Meta.Title);
  
  // Create a safe filename
  SafeTitle := Meta.Title;
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

    if TargetFolder <> '' then
    begin
      OutputPath := IncludeTrailingPathDelimiter(AppConfig.InputPath) + TargetFolder;
      if not DirectoryExists(OutputPath) then ForceDirectories(OutputPath);
      OutputPath := OutputPath + DirectorySeparator + SafeTitle + FileExt;
    end
    else
      OutputPath := IncludeTrailingPathDelimiter(AppConfig.InputPath) + SafeTitle + FileExt;

    WriteLn('  [+] Downloading stream...');
    FS := TFileStream.Create(OutputPath, fmCreate);
    try
      DownloadClient := TFPHTTPClient.Create(nil);
      try
        DownloadClient.Get(StreamUrl, FS);
      finally DownloadClient.Free; end;
    finally FS.Free; end;
    WriteLn('  [+] Saved as ', OutputPath);

    // Attach metadata
    TagFile(OutputPath, Meta);

  except
    on E: Exception do WriteLn('  [!] Error downloading track: ', E.Message);
  end;
end;

procedure TMusicProviderAPI.DownloadMedia(const MediaType: string; const URLOrId: string);
var
  Id, Response, TrackId: string;
  Metadata, TrackObj, ArtistObj, AlbumObj: TJSONObject;
  ItemsArray: TJSONArray;
  Parser: TJSONParser;
  i: Integer;
  Meta: TMetaData;
  TargetFolder: string;
begin
  Id := ExtractIdFromUrl(URLOrId);
  TargetFolder := '';
  
  if MediaType = 'track' then
  begin
    Metadata := FetchMediaMetadata(MediaType, Id);
    if Assigned(Metadata) then
    begin
      try
        FillChar(Meta, SizeOf(Meta), 0);
        Meta.Title := Metadata.Strings['title'];
        Meta.Artist := Metadata.Objects['artist'].Strings['name'];
        if Metadata.Find('album') <> nil then
        begin
          AlbumObj := Metadata.Objects['album'];
          Meta.Album := AlbumObj.Strings['title'];
          if AlbumObj.Find('cover') <> nil then
            Meta.CoverUUID := AlbumObj.Strings['cover'];
        end;
        Meta.TrackNumber := Metadata.Integers['trackNumber'];
        Meta.DiscNumber := Metadata.Integers['volumeNumber'];
        if Metadata.Find('isrc') <> nil then Meta.ISRC := Metadata.Strings['isrc'];
        if Metadata.Find('copyright') <> nil then Meta.Copyright := Metadata.Strings['copyright'];
        Meta.Comment := 'https://tidal.com/track/' + Id;

        DownloadTrack(Id, Meta, '');
      finally Metadata.Free; end;
    end;
  end
  else if MediaType = 'album' then
  begin
    WriteLn('Fetching album metadata...');
    Metadata := FetchMediaMetadata(MediaType, Id);
    if Assigned(Metadata) then
    begin
      try
        FillChar(Meta, SizeOf(Meta), 0);
        Meta.Album := Metadata.Strings['title'];
        ArtistObj := Metadata.Objects['artist'];
        Meta.Artist := ArtistObj.Strings['name'];
        if Metadata.Find('cover') <> nil then Meta.CoverUUID := Metadata.Strings['cover'];
        if Metadata.Find('releaseDate') <> nil then Meta.ReleaseDate := Metadata.Strings['releaseDate'];
        if Metadata.Find('upc') <> nil then Meta.UPC := Metadata.Strings['upc'];
        if Metadata.Find('copyright') <> nil then Meta.Copyright := Metadata.Strings['copyright'];
        Meta.Comment := 'https://tidal.com/album/' + Id;
          
        TargetFolder := Meta.Artist + ' - ' + Meta.Album;
        // Sanitize folder name
        for i := 1 to Length(TargetFolder) do
          if TargetFolder[i] in ['\', '/', ':', '*', '?', '"', '<', '>', '|'] then
            TargetFolder[i] := '_';
            
        WriteLn('Target directory: ', TargetFolder);
      finally Metadata.Free; end;
    end;

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
              
              Meta.Title := TrackObj.Strings['title'];
              Meta.TrackNumber := TrackObj.Integers['trackNumber'];
              Meta.DiscNumber := TrackObj.Integers['volumeNumber'];
              if TrackObj.Find('isrc') <> nil then Meta.ISRC := TrackObj.Strings['isrc'];
              if TrackObj.Find('artist') <> nil then
                Meta.Artist := TrackObj.Objects['artist'].Strings['name'];

              WriteLn(Format('Downloading track %d/%d...', [i+1, ItemsArray.Count]));
              DownloadTrack(TrackId, Meta, TargetFolder);
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

