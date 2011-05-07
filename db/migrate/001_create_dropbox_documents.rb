# Encoding: UTF-8
#	Written by: Signo-Net
#	Email: clientes@signo-net.com 
#	Web: http://www.signo-net.com 

# This work is licensed under a Creative Commons Attribution 3.0 License.
# [ http://creativecommons.org/licenses/by/3.0/ ]

# This means you may use it for any purpose, and make any changes you like.
# All we ask is that you include a link back to our page in your credits.

# Looking forward your comments and suggestions! clientes@signo-net.com

class CreateDropboxDocuments < ActiveRecord::Migration
  def self.up
    create_table :dropbox_documents do |t|
      t.column :project_id, :integer
      t.column :category_id, :integer
      t.column :author_id, :integer
      t.column :title, :string
      t.column :description, :text
      t.column :ruta, :text
      t.column :created_on, :datetime
      t.column :updated_on, :datetime
    end

    create_table :dropbox_attachments do |t|
      t.column :dropbox_document_id, :integer, :null => false
      t.column :author_id, :integer
      t.column :filesize, :integer
      t.column :content_type, :string
      t.column :description, :text
      t.column :ruta, :text
      t.column :created_on, :datetime
      t.column :updated_on, :datetime
    end

    add_index "dropbox_documents", ["project_id"], :name => "dropbox_documents_project_id"
  end

  def self.down
    drop_table :dropbox_documents
    drop_table :dropbox_attachments
  end
end
