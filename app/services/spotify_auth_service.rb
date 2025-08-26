require 'net/http'
require 'json'
require 'base64'
require 'uri'

class SpotifyAuthService
  SPOTIFY_ACCOUNTS_BASE = 'https://accounts.spotify.com'
  
  def self.refresh_token(refresh_token)
    uri = URI("#{SPOTIFY_ACCOUNTS_BASE}/api/token")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    
    request = Net::HTTP::Post.new(uri)
    
    # Clean credentials to avoid CR/LF issues
    client_id = ENV['SPOTIFY_CLIENT_ID'].to_s.strip
    client_secret = ENV['SPOTIFY_CLIENT_SECRET'].to_s.strip
    auth_string = Base64.encode64("#{client_id}:#{client_secret}").strip.gsub(/\r\n|\r|\n/, '')
    
    request['Authorization'] = "Basic #{auth_string}"
    request['Content-Type'] = 'application/x-www-form-urlencoded'
    
    request.body = "grant_type=refresh_token&refresh_token=#{refresh_token}"
    
    response = http.request(request)
    
    if response.code == '200'
      JSON.parse(response.body)
    else
      Rails.logger.error "Token refresh failed: #{response.code} - #{response.body}"
      nil
    end
  rescue => e
    Rails.logger.error "Token refresh error: #{e.class.name}: #{e.message}"
    nil
  end
end