unit uMusicProviderConstants;

{
  MusicProvider API Constants
  Contains fixed configuration for API keys, endpoints, and local storage.
}
{$mode objfpc}{$H+}

interface

const
  { The underlying provider domain for URL parsing }
  PROVIDER_DOMAIN   = 'tidal.com';

  { API Credentials (extracted from Android Auto client) }
  API_CLIENT_ID     = 'fX2JxdmntZWK0ixT';
  API_CLIENT_SECRET = '1Nn9AfDAjxrgJFJbKNWLeAyKGVGmINuXPPLHVXAvxAg=';

  { Local storage for the OAuth2 session }
  TOKEN_FILE        = 'tidal_token.json';

  { Regional settings for API results }
  COUNTRY_CODE      = 'US';

  { MusicProvider OAuth2 and API Endpoints }
  URL_AUTH_DEVICE   = 'https://auth.tidal.com/v1/oauth2/device_authorization';
  URL_AUTH_TOKEN    = 'https://auth.tidal.com/v1/oauth2/token';
  URL_API_BASE      = 'https://api.tidal.com/v1/';

implementation

end.

