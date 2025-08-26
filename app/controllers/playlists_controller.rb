class PlaylistsController < ApplicationController

  def create
    unless ENV['SPOTIFY_USER_ID'].present?
      render json: { 
        success: false, 
        error: "Spotify não configurado. Acesse http://localhost:3000/auth/spotify para configurar.",
        redirect_to_auth: true
      }, status: :unprocessable_entity
      return
    end

    playlist_params = params.require(:playlist).permit(:mood, :era, :additional_preferences, genres: [])
    
    # Generate playlist using Claude AI
    playlist_service = PlaylistGeneratorService.new
    generated_tracks = playlist_service.generate_playlist(playlist_params)
    
    if generated_tracks.present?
      # Create actual playlist on Spotify
      spotify_service = SpotifyService.new
      playlist_url = spotify_service.create_playlist(generated_tracks, playlist_params)
      
      if playlist_url
        render json: { 
          success: true, 
          playlist_url: playlist_url,
          tracks: generated_tracks,
          message: "✅ Playlist criada no seu Spotify!"
        }
      else
        render json: { 
          success: false, 
          error: "Erro ao criar playlist no Spotify. Verifique as configurações." 
        }, status: :unprocessable_entity
      end
    else
      render json: { 
        success: false, 
        error: "Erro ao gerar playlist com IA" 
      }, status: :unprocessable_entity
    end
  rescue => e
    Rails.logger.error "Playlist creation error: #{e.message}"
    render json: { 
      success: false, 
      error: "Erro interno do servidor" 
    }, status: :internal_server_error
  end

  private
end