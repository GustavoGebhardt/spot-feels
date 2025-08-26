class SpotifyToken < ApplicationRecord
  validates :user_id, presence: true, uniqueness: true
  validates :access_token, presence: true
  
  def self.current
    first
  end
  
  def expired?
    expires_at && expires_at < Time.current
  end
  
  def refresh_if_needed!
    return self unless expired? && refresh_token.present?
    
    refreshed_tokens = SpotifyAuthService.refresh_token(refresh_token)
    
    if refreshed_tokens
      update!(
        access_token: refreshed_tokens['access_token'],
        expires_at: Time.current + refreshed_tokens['expires_in'].seconds,
        refresh_token: refreshed_tokens['refresh_token'] || refresh_token
      )
    end
    
    self
  end
end