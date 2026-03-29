unit uMusicProviderAuth;

{
  MusicProvider Authentication Manager
  Handles the OAuth2 Device Flow and persistence of access tokens.
}
{$mode objfpc}{$H+}

interface

uses SysUtils, Classes, fphttpclient, fpjson, jsonparser, jsonscanner, uMusicProviderConstants;

type
  TMusicProviderAuth = class
  protected
    FHttpClient: TFPHTTPClient;
    FAccessToken: string;
    FRefreshToken: string;
    procedure SaveSessionToFile;
    procedure LoadSessionFromFile;
    function ExecutePost(const URL: string; const PostData: string): string;
  public
    constructor Create;
    destructor Destroy; override;
    function Login: Boolean;
    property HttpClient: TFPHTTPClient read FHttpClient;
  end;

implementation

constructor TMusicProviderAuth.Create;
begin
  FHttpClient := TFPHTTPClient.Create(nil);
  FHttpClient.AllowRedirect := True;
  FHttpClient.AddHeader('x-tidal-client-version', '2025.7.16');
  FHttpClient.AddHeader('User-Agent', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36');
end;

destructor TMusicProviderAuth.Destroy;
begin
  FHttpClient.Free;
  inherited Destroy;
end;

procedure TMusicProviderAuth.SaveSessionToFile;
var JSON: TJSONObject; SL: TStringList;
begin
  JSON := TJSONObject.Create; SL := TStringList.Create;
  try
    JSON.Add('access_token', FAccessToken);
    JSON.Add('refresh_token', FRefreshToken);
    SL.Text := JSON.AsJSON;
    SL.SaveToFile(TOKEN_FILE);
  finally JSON.Free; SL.Free; end;
end;

procedure TMusicProviderAuth.LoadSessionFromFile;
var JSON: TJSONObject; Parser: TJSONParser; SL: TStringList;
begin
  if not FileExists(TOKEN_FILE) then Exit;
  SL := TStringList.Create;
  try
    SL.LoadFromFile(TOKEN_FILE);
    Parser := TJSONParser.Create(SL.Text, [joUTF8]);
    JSON := Parser.Parse as TJSONObject;
    FAccessToken := JSON.Strings['access_token'];
    FRefreshToken := JSON.Strings['refresh_token'];
    JSON.Free; Parser.Free;
  finally SL.Free; end;
end;

function TMusicProviderAuth.ExecutePost(const URL: string; const PostData: string): string;
begin
  FHttpClient.AddHeader('Content-Type', 'application/x-www-form-urlencoded');
  FHttpClient.RequestBody := TStringStream.Create(PostData);
  try
    Result := FHttpClient.Post(URL);
  finally
    FHttpClient.RequestBody.Free;
    FHttpClient.RequestBody := nil;
  end;
end;

function TMusicProviderAuth.Login: Boolean;
var
  PostData, Response, VerifURL, UserCode, DeviceCode: string;
  JSON, AuthData: TJSONObject;
  Parser: TJSONParser;
  PollIntervalSec: Integer;
begin
  Result := False; LoadSessionFromFile;
  if FAccessToken <> '' then
  begin
    FHttpClient.AddHeader('Authorization', 'Bearer ' + FAccessToken);
    try
      FHttpClient.Get(URL_API_BASE + 'sessions');
      WriteLn('Session resumed successfully.');
      Exit(True);
    except 
      on E: Exception do
      begin
        WriteLn('Token expired or validation failed: ', E.Message);
        if FHttpClient.ResponseStatusCode <> 0 then
          WriteLn('HTTP Status Code: ', FHttpClient.ResponseStatusCode);
        // Continue to new login flow
      end;
    end;
  end;

  PostData := 'client_id=' + API_CLIENT_ID + '&scope=r_usr%20w_usr%20w_sub';
  Response := ExecutePost(URL_AUTH_DEVICE, PostData);
  Parser := TJSONParser.Create(Response, [joUTF8]);
  AuthData := Parser.Parse as TJSONObject;
  
  if AuthData.Find('deviceCode') = nil then
  begin
    WriteLn('Error: Authorization response does not contain "deviceCode".');
    WriteLn('Server response: ', Response);
    AuthData.Free; Parser.Free;
    Exit(False);
  end;

  DeviceCode := AuthData.Strings['deviceCode'];
  UserCode := AuthData.Strings['userCode'];
  VerifURL := AuthData.Strings['verificationUriComplete'];
  PollIntervalSec := AuthData.Integers['interval'];
  AuthData.Free; Parser.Free;

  WriteLn('Please authorize this app at: ' + VerifURL);

  PostData := 'client_id=' + API_CLIENT_ID + '&device_code=' + DeviceCode + 
              '&grant_type=urn:ietf:params:oauth:grant-type:device_code' + 
              '&client_secret=' + API_CLIENT_SECRET + '&scope=r_usr%20w_usr%20w_sub';

  while True do
  begin
    Sleep(PollIntervalSec * 1000);
    try
      try
        Response := ExecutePost(URL_AUTH_TOKEN, PostData);
      except 
        on E: EHTTPClient do 
        begin
          // If it's a 400 Bad Request, it usually means authorization_pending. Keep polling.
          if FHttpClient.ResponseStatusCode = 400 then 
            Continue
          else 
          begin
            WriteLn('Auth error: ', E.Message);
            Exit(False); 
          end;
        end;
      end;

      if Response = '' then Continue;

      Parser := TJSONParser.Create(Response, [joUTF8]);
      try
        JSON := Parser.Parse as TJSONObject;
        try
          if JSON.Find('access_token') <> nil then
          begin
            FAccessToken := JSON.Strings['access_token'];
            FRefreshToken := JSON.Strings['refresh_token'];
            SaveSessionToFile;
            FHttpClient.AddHeader('Authorization', 'Bearer ' + FAccessToken);
            Exit(True);
          end
          else if JSON.Find('error') <> nil then
          begin
            if JSON.Strings['error'] <> 'authorization_pending' then
            begin
              WriteLn('Authorization failed: ', JSON.Strings['error']);
              Exit(False);
            end;
            // Otherwise it's still pending, so we just loop again
          end;
        finally
          JSON.Free;
        end;
      finally
        Parser.Free;
      end;

    except 
      on E: Exception do
      begin
         WriteLn('Unexpected error: ', E.Message);
         Exit(False);
      end;
    end;
  end;
end;

end.

