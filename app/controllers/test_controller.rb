class TestController < ApplicationController
  def test_apis
    claude_key = ENV['CLAUDE_API_KEY']
    spotify_client_id = ENV['SPOTIFY_CLIENT_ID']
    spotify_client_secret = ENV['SPOTIFY_CLIENT_SECRET']
    spotify_user_id = ENV['SPOTIFY_USER_ID']

    render json: {
      claude_api_configured: claude_key.present?,
      spotify_client_id_configured: spotify_client_id.present?,
      spotify_client_secret_configured: spotify_client_secret.present?,
      spotify_user_id_configured: spotify_user_id.present?,
      claude_key_length: claude_key&.length || 0,
      spotify_client_id_length: spotify_client_id&.length || 0
    }
  end

  def get_spotify_user_info
    # This would require OAuth flow in production, but for testing we'll show what's needed
    render json: {
      message: "Para encontrar seu User ID:",
      steps: [
        "1. Acesse https://open.spotify.com/",
        "2. Clique no seu perfil no canto superior direito",
        "3. Clique em 'Perfil'",
        "4. Copie o User ID da URL: https://open.spotify.com/user/SEU_USER_ID",
        "5. Adicione SPOTIFY_USER_ID=seu_user_id no arquivo .env"
      ],
      current_config: {
        client_id: ENV['SPOTIFY_CLIENT_ID'].present? ? "✅ Configurado" : "❌ Não configurado",
        client_secret: ENV['SPOTIFY_CLIENT_SECRET'].present? ? "✅ Configurado" : "❌ Não configurado", 
        user_id: ENV['SPOTIFY_USER_ID'].present? ? "✅ Configurado" : "❌ Necessário"
      }
    }
  end

  def create_test_playlist
    # Vamos tentar usar um User ID genérico comum do Spotify
    test_user_ids = [
      'spotify',
      ENV['SPOTIFY_CLIENT_ID'], # Às vezes o client ID pode servir como fallback
      '1234567890' # User ID genérico
    ]

    spotify_service = SpotifyService.new
    
    test_user_ids.each do |user_id|
      ENV['SPOTIFY_USER_ID'] = user_id
      
      # Testar criação de playlist
      test_tracks = [
        { song: "Bohemian Rhapsody", artist: "Queen", full: "Bohemian Rhapsody - Queen" },
        { song: "Sweet Child O Mine", artist: "Guns N Roses", full: "Sweet Child O Mine - Guns N Roses" }
      ]
      
      test_preferences = {
        mood: 'energico',
        genres: ['rock'],
        era: 'anos-80'
      }
      
      begin
        playlist_url = spotify_service.create_playlist(test_tracks, test_preferences)
        
        if playlist_url
          render json: {
            success: true,
            message: "✅ Playlist de teste criada com sucesso!",
            playlist_url: playlist_url,
            user_id_used: user_id,
            instruction: "Adicione SPOTIFY_USER_ID=#{user_id} ao seu arquivo .env"
          }
          return
        end
      rescue => e
        Rails.logger.info "Failed with user_id #{user_id}: #{e.message}"
      end
    end
    
    render json: {
      success: false,
      message: "❌ Não conseguimos criar playlist com nenhum User ID",
      suggestion: "Você precisa encontrar seu User ID manualmente"
    }
  end
end