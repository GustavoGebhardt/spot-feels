require 'net/http'
require 'json'

class PlaylistGeneratorService
  CLAUDE_API_URL = 'https://api.anthropic.com/v1/messages'
  
  def initialize
    @api_key = ENV['CLAUDE_API_KEY']
  end

  def generate_playlist(preferences)
    prompt = build_prompt(preferences)
    
    response = call_claude_api(prompt)
    parse_tracks_from_response(response)
  rescue => e
    Rails.logger.error "Claude API error: #{e.message}"
    []
  end

  private

  def build_prompt(preferences)
    genres_text = preferences[:genres]&.join(", ") || "todos os gêneros"
    era_text = preferences[:era] || "todas as épocas"
    mood_text = preferences[:mood] || "neutro"
    additional = preferences[:additional_preferences].presence || "nenhuma preferência adicional"

    <<~PROMPT
      Você é um especialista em música e curadoria de playlists. Crie uma playlist de 20 músicas baseada nas seguintes preferências:

      - Humor/Sentimento: #{mood_text}
      - Gêneros preferidos: #{genres_text}
      - Época: #{era_text}
      - Preferências adicionais: #{additional}

      IMPORTANTE: Retorne apenas uma lista das músicas no formato exato:
      "Nome da Música - Artista"

      Uma música por linha, sem numeração, sem explicações adicionais. Apenas o nome da música seguido de hífen e o nome do artista.
      
      Exemplo:
      Bohemian Rhapsody - Queen
      Imagine - John Lennon

      Inclua uma mistura de músicas populares e algumas menos conhecidas que se encaixem perfeitamente no mood solicitado.
    PROMPT
  end

  def call_claude_api(prompt)
    models_to_try = [
      "claude-3-haiku-20240307"
    ]
    
    models_to_try.each do |model|
      response = try_claude_model(prompt, model)
      return response if response
    end
    
    Rails.logger.error "All Claude models failed"
    nil
  end

  def try_claude_model(prompt, model)
    Rails.logger.info "Trying Claude model: #{model}"
    
    uri = URI(CLAUDE_API_URL)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    
    request = Net::HTTP::Post.new(uri)
    request['Content-Type'] = 'application/json'
    request['x-api-key'] = @api_key.to_s.strip
    request['anthropic-version'] = '2023-06-01'
    
    # Clean the prompt to avoid any CR/LF issues
    clean_prompt = prompt.gsub(/\r\n|\r|\n/, ' ').strip
    
    request.body = {
      model: model,
      max_tokens: 1024,
      messages: [
        {
          role: "user",
          content: clean_prompt
        }
      ]
    }.to_json

    Rails.logger.info "Making request to Claude API"
    response = http.request(request)
    Rails.logger.info "Claude API response code: #{response.code}"
    
    if response.code == '200'
      JSON.parse(response.body)
    else
      Rails.logger.warn "Claude model #{model} failed: #{response.code} - #{response.body}"
      nil
    end
  rescue => e
    Rails.logger.error "Claude API request error: #{e.class.name}: #{e.message}"
    nil
  end

  def parse_tracks_from_response(response)
    return [] unless response && response['content']
    
    content = response['content'].first['text']
    tracks = []
    
    content.split("\n").each do |line|
      line = line.strip
      next if line.empty?
      
      # Parse "Song Name - Artist" format
      if line.match(/^(.+?) - (.+)$/)
        song = $1.strip
        artist = $2.strip
        tracks << { song: song, artist: artist, full: "#{song} - #{artist}" }
      end
    end
    
    tracks
  end
end