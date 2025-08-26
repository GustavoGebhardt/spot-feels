require 'net/http'
require 'json'
require 'base64'
require 'uri'

class SpotifyAuthController < ApplicationController
  def authorize
    # Redirect user to Spotify authorization
    client_id = ENV['SPOTIFY_CLIENT_ID']
    redirect_uri = ENV['SPOTIFY_REDIRECT_URI'] || "http://localhost:3000/auth/spotify/callback"
    
    scope = "playlist-modify-public playlist-modify-private user-read-private"
    
    auth_url = "https://accounts.spotify.com/authorize?" +
               "client_id=#{client_id}&" +
               "response_type=code&" +
               "redirect_uri=#{redirect_uri}&" +
               "scope=#{scope}"
    
    redirect_to auth_url, allow_other_host: true
  end

  def callback
    code = params[:code]
    error = params[:error]
    
    if error
      render json: { error: "Spotify authorization failed: #{error}" }, status: :bad_request
      return
    end
    
    # Exchange code for access token
    token_data = exchange_code_for_token(code)
    
    if token_data
      # Get user profile
      user_profile = get_spotify_user_profile(token_data['access_token'])
      
      if user_profile
        # Save tokens to database
        spotify_token = SpotifyToken.find_or_initialize_by(user_id: user_profile['id'])
        spotify_token.update!(
          access_token: token_data['access_token'],
          refresh_token: token_data['refresh_token'],
          expires_at: Time.current + token_data['expires_in'].seconds
        )
        
        render json: {
          success: true,
          message: "✅ Conectado ao Spotify com sucesso!",
          user_id: user_profile['id'],
          display_name: user_profile['display_name'],
          instruction: "Tokens salvos! Adicione esta linha ao seu .env: SPOTIFY_USER_ID=#{user_profile['id']}",
          tokens_saved: true
        }
      else
        render json: { error: "Não foi possível obter perfil do usuário" }, status: :unprocessable_entity
      end
    else
      render json: { error: "Falha na troca do código por token" }, status: :unprocessable_entity
    end
  end

  private

  def exchange_code_for_token(code)
    uri = URI("https://accounts.spotify.com/api/token")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    
    request = Net::HTTP::Post.new(uri)
    
    # Clean credentials to avoid CR/LF issues
    client_id = ENV['SPOTIFY_CLIENT_ID'].to_s.strip
    client_secret = ENV['SPOTIFY_CLIENT_SECRET'].to_s.strip
    auth_string = Base64.encode64("#{client_id}:#{client_secret}").strip.gsub(/\r\n|\r|\n/, '')
    
    request['Authorization'] = "Basic #{auth_string}"
    request['Content-Type'] = 'application/x-www-form-urlencoded'
    
    redirect_uri = ENV['SPOTIFY_REDIRECT_URI'] || "http://localhost:3000/auth/spotify/callback"
    
    request.body = "grant_type=authorization_code&code=#{code}&redirect_uri=#{redirect_uri}"
    
    response = http.request(request)
    
    if response.code == '200'
      JSON.parse(response.body)
    else
      Rails.logger.error "Token exchange failed: #{response.code} - #{response.body}"
      nil
    end
  rescue => e
    Rails.logger.error "Token exchange error: #{e.class.name}: #{e.message}"
    nil
  end

  def get_spotify_user_profile(access_token)
    uri = URI("https://api.spotify.com/v1/me")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    
    request = Net::HTTP::Get.new(uri)
    # Clean access token to avoid CR/LF issues
    clean_token = access_token.to_s.strip.gsub(/\r\n|\r|\n/, '')
    request['Authorization'] = "Bearer #{clean_token}"
    
    response = http.request(request)
    
    if response.code == '200'
      JSON.parse(response.body)
    else
      Rails.logger.error "Profile fetch failed: #{response.code} - #{response.body}"
      nil
    end
  rescue => e
    Rails.logger.error "Profile fetch error: #{e.class.name}: #{e.message}"
    nil
  end
end