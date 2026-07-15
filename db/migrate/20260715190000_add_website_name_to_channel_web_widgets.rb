class AddWebsiteNameToChannelWebWidgets < ActiveRecord::Migration[7.1]
  def change
    add_column :channel_web_widgets, :website_name, :string
  end
end
