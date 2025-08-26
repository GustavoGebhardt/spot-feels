class CreateSpotifyTokens < ActiveRecord::Migration[8.0]
  def change
    create_table :spotify_tokens do |t|
      t.string :user_id
      t.text :access_token
      t.text :refresh_token
      t.datetime :expires_at

      t.timestamps
    end
  end
end
