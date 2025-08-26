require 'net/http'
require 'json'
require 'base64'
require 'uri'

class SpotifyService
  SPOTIFY_API_BASE = 'https://api.spotify.com/v1'
  SPOTIFY_ACCOUNTS_BASE = 'https://accounts.spotify.com'
  
  def initialize
    @client_id = ENV['SPOTIFY_CLIENT_ID']
    @client_secret = ENV['SPOTIFY_CLIENT_SECRET']
    
    # Try to get user token first, fallback to client credentials
    spotify_token = SpotifyToken.current
    if spotify_token
      spotify_token.refresh_if_needed!
      @access_token = spotify_token.access_token
      @token_type = :user
      Rails.logger.info "Using user access token"
    else
      @access_token = get_client_credentials_token
      @token_type = :client
      Rails.logger.info "Using client credentials token (limited functionality)"
    end
  end

  def validate_and_search_tracks(tracks)
    return [] unless @access_token
    
    Rails.logger.info "Validating #{tracks.length} tracks on Spotify"
    
    validated_tracks = []
    
    tracks.each_with_index do |track, index|
      Rails.logger.info "Searching track #{index + 1}/#{tracks.length}: #{track[:song]} - #{track[:artist]}"
      
      spotify_track = search_track_details(track[:song], track[:artist])
      
      if spotify_track
        validated_tracks << {
          original_suggestion: track[:full],
          song: spotify_track[:name],
          artist: spotify_track[:artist],
          album: spotify_track[:album],
          spotify_url: spotify_track[:url],
          preview_url: spotify_track[:preview_url],
          found: true
        }
      else
        validated_tracks << {
          original_suggestion: track[:full],
          song: track[:song],
          artist: track[:artist],
          found: false,
          message: "Não encontrada no Spotify"
        }
      end
      
      # Small delay to avoid rate limiting
      sleep(0.1)
    end
    
    Rails.logger.info "Found #{validated_tracks.count { |t| t[:found] }}/#{tracks.length} tracks on Spotify"
    
    validated_tracks
  rescue => e
    Rails.logger.error "Spotify validation error: #{e.class.name}: #{e.message}"
    []
  end

  def create_playlist(tracks, preferences)
    return nil unless @access_token
    
    if @token_type != :user
      Rails.logger.error "Cannot create playlists without user authentication"
      return nil
    end
    
    Rails.logger.info "Creating playlist with #{tracks.length} tracks using user token"
    
    playlist_name = generate_playlist_name(preferences)
    playlist_description = generate_playlist_description(preferences)
    
    Rails.logger.info "Playlist name: #{playlist_name}"
    Rails.logger.info "Playlist description: #{playlist_description}"
    
    # Create playlist
    playlist_id = create_spotify_playlist(playlist_name, playlist_description)
    return nil unless playlist_id
    
    Rails.logger.info "Created playlist with ID: #{playlist_id}"
    
    # Search for tracks and add to playlist
    track_uris = search_and_get_track_uris(tracks)
    
    Rails.logger.info "Found #{track_uris.length} track URIs"
    
    if track_uris.any?
      add_tracks_to_playlist(playlist_id, track_uris)
      "https://open.spotify.com/playlist/#{playlist_id}"
    else
      Rails.logger.warn "No tracks found to add to playlist"
      nil
    end
  rescue => e
    Rails.logger.error "Spotify API error: #{e.class.name}: #{e.message}"
    Rails.logger.error e.backtrace.first(5).join("\n")
    nil
  end

  def generate_playlist_name(preferences)
    mood_translations = {
      'feliz' => 'Happy',
      'relaxado' => 'Relaxed',
      'energico' => 'Energetic',
      'melancolico' => 'Melancholic',
      'motivado' => 'Motivated',
      'nostalgico' => 'Nostalgic',
      'romantico' => 'Romantic',
      'focado' => 'Focused'
    }
    
    mood = mood_translations[preferences[:mood]] || "Custom"
    timestamp = Time.current.strftime("%d-%m")
    
    "SpotFeels #{mood} #{timestamp}"
  end

  def generate_playlist_description(preferences)
    mood = preferences[:mood] || "custom"
    genres = preferences[:genres]&.join(", ") || "various genres"
    era = preferences[:era] || "all eras"
    
    "AI-generated playlist by SpotFeels. Mood: #{mood}. Genres: #{genres}. Era: #{era}."
  end

  private

  def get_client_credentials_token
    Rails.logger.info "Getting Spotify access token"
    
    uri = URI("#{SPOTIFY_ACCOUNTS_BASE}/api/token")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    
    request = Net::HTTP::Post.new(uri)
    # Clean the credentials to avoid any CR/LF issues
    clean_client_id = @client_id.to_s.strip
    clean_client_secret = @client_secret.to_s.strip
    auth_string = Base64.encode64("#{clean_client_id}:#{clean_client_secret}").strip.gsub(/\r\n|\r|\n/, '')
    
    request['Authorization'] = "Basic #{auth_string}"
    request['Content-Type'] = 'application/x-www-form-urlencoded'
    request.body = 'grant_type=client_credentials'
    
    Rails.logger.info "Making Spotify auth request"
    response = http.request(request)
    Rails.logger.info "Spotify auth response code: #{response.code}"
    
    if response.code == '200'
      token = JSON.parse(response.body)['access_token']
      Rails.logger.info "Successfully obtained Spotify access token"
      token
    else
      Rails.logger.error "Spotify auth error: #{response.code} - #{response.body}"
      nil
    end
  rescue => e
    Rails.logger.error "Spotify auth request error: #{e.class.name}: #{e.message}"
    nil
  end

  def create_spotify_playlist(name, description)
    # Try different approaches to create playlist
    user_id = ENV['SPOTIFY_USER_ID']
    
    if user_id
      Rails.logger.info "Creating playlist for configured user: #{user_id}"
      return create_playlist_for_user(user_id, name, description)
    end
    
    # Fallback: Try to get current user and create playlist
    Rails.logger.info "No user ID configured, trying to get current user"
    current_user_id = get_current_user_id
    
    if current_user_id
      Rails.logger.info "Got current user ID: #{current_user_id}"
      Rails.logger.info "Add this to your .env file: SPOTIFY_USER_ID=#{current_user_id}"
      return create_playlist_for_user(current_user_id, name, description)
    end
    
    Rails.logger.error "Could not determine user ID for playlist creation"
    nil
  end

  def get_current_user_id
    # This requires user authentication, but let's try anyway
    uri = URI("#{SPOTIFY_API_BASE}/me")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    
    request = Net::HTTP::Get.new(uri)
    clean_token = @access_token.to_s.strip.gsub(/\r\n|\r|\n/, '')
    request['Authorization'] = "Bearer #{clean_token}"
    
    response = http.request(request)
    
    if response.code == '200'
      user_data = JSON.parse(response.body)
      user_data['id']
    else
      Rails.logger.warn "Could not get current user: #{response.code} - #{response.body}"
      nil
    end
  rescue => e
    Rails.logger.warn "Error getting current user: #{e.message}"
    nil
  end

  def create_playlist_for_user(user_id, name, description)
    uri = URI("#{SPOTIFY_API_BASE}/users/#{user_id}/playlists")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    
    request = Net::HTTP::Post.new(uri)
    # Clean the access token
    clean_token = @access_token.to_s.strip.gsub(/\r\n|\r|\n/, '')
    request['Authorization'] = "Bearer #{clean_token}"
    request['Content-Type'] = 'application/json'
    
    # Clean name and description
    clean_name = name.to_s.strip.gsub(/\r\n|\r|\n/, ' ')
    clean_description = description.to_s.strip.gsub(/\r\n|\r|\n/, ' ')
    
    request.body = {
      name: clean_name,
      description: clean_description,
      public: true
    }.to_json
    
    Rails.logger.info "Making create playlist request for user: #{user_id}"
    response = http.request(request)
    Rails.logger.info "Create playlist response code: #{response.code}"
    
    if response.code == '201'
      playlist_id = JSON.parse(response.body)['id']
      Rails.logger.info "Successfully created playlist: #{playlist_id}"
      playlist_id
    else
      Rails.logger.error "Spotify playlist creation error: #{response.code} - #{response.body}"
      nil
    end
  rescue => e
    Rails.logger.error "Spotify playlist creation request error: #{e.class.name}: #{e.message}"
    nil
  end

  def search_and_get_track_uris(tracks)
    track_uris = []
    
    tracks.each do |track|
      uri = search_track(track[:song], track[:artist])
      track_uris << uri if uri
      
      # Add small delay to avoid rate limiting
      sleep(0.1)
    end
    
    track_uris
  end

  def search_track_details(song, artist)
    # Clean and encode the search query properly
    clean_song = song.to_s.strip.gsub(/[^\w\s-]/, '')
    clean_artist = artist.to_s.strip.gsub(/[^\w\s-]/, '')
    query = "#{clean_song} artist:#{clean_artist}"
    encoded_query = URI.encode_www_form_component(query)
    
    uri = URI("#{SPOTIFY_API_BASE}/search?q=#{encoded_query}&type=track&limit=1")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    
    request = Net::HTTP::Get.new(uri)
    clean_token = @access_token.to_s.strip.gsub(/\r\n|\r|\n/, '')
    request['Authorization'] = "Bearer #{clean_token}"
    
    response = http.request(request)
    
    if response.code == '200'
      data = JSON.parse(response.body)
      tracks = data['tracks']['items']
      
      if tracks.any?
        track = tracks.first
        {
          name: track['name'],
          artist: track['artists'].first['name'],
          album: track['album']['name'],
          url: track['external_urls']['spotify'],
          preview_url: track['preview_url'],
          uri: track['uri']
        }
      else
        nil
      end
    else
      Rails.logger.error "Spotify search error: #{response.code} - #{response.body}"
      nil
    end
  rescue => e
    Rails.logger.error "Spotify search request error: #{e.class.name}: #{e.message}"
    nil
  end

  def search_track(song, artist)
    track_details = search_track_details(song, artist)
    track_details ? track_details[:uri] : nil
  end

  def add_tracks_to_playlist(playlist_id, track_uris)
    return if track_uris.empty?
    
    Rails.logger.info "Adding #{track_uris.length} tracks to playlist #{playlist_id}"
    
    uri = URI("#{SPOTIFY_API_BASE}/playlists/#{playlist_id}/tracks")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    
    request = Net::HTTP::Post.new(uri)
    # Clean the access token
    clean_token = @access_token.to_s.strip.gsub(/\r\n|\r|\n/, '')
    request['Authorization'] = "Bearer #{clean_token}"
    request['Content-Type'] = 'application/json'
    
    request.body = { uris: track_uris }.to_json
    
    Rails.logger.info "Making add tracks request"
    response = http.request(request)
    Rails.logger.info "Add tracks response code: #{response.code}"
    
    if response.code == '201'
      Rails.logger.info "Successfully added tracks to playlist"
    else
      Rails.logger.error "Spotify add tracks error: #{response.code} - #{response.body}"
    end
  rescue => e
    Rails.logger.error "Spotify add tracks request error: #{e.class.name}: #{e.message}"
  end

end