# Encoding: UTF-8
#	Written by: Zuinq Studio
#	Email: info@zuinqstudio.com 
#	Web: http://www.zuinqstudio.com 

# This work is licensed under a Creative Commons Attribution 3.0 License.
# [ http://creativecommons.org/licenses/by/3.0/ ]

# This means you may use it for any purpose, and make any changes you like.
# All we ask is that you include a link back to our page in your credits.

# Looking forward your comments and suggestions! clientes@signo-net.com

require 'redmine'
require 'oauth'
require 'json'
require 'uri'
require 'net/http/post/multipart'


Redmine::Plugin.register :redmine_drop_box do
	name 'Redmine Dropbox Plugin'
	author 'Zuinq Studio'
	description 'Storage proyect files on your Dropbox account'
	version '0.0.1'
	url 'http://www.zuinqstudio.com/labs/'
	author_url 'http://www.zuinqstudio.com'

	menu :project_menu, :drop_box, { :controller => 'drop_box', :action => 'index' }, :caption => 'Dropbox', :after => :documents, :param => :project_id

	settings :default => {
		'DROPBOX_SESSION' => nil,
		'PATH_BASE_DOCUMENTOS' => 'REDMINE'
	}, :partial => 'settings/dropbox_settings'

	project_module :drop_box do
		permission :view_dropbox_documents, :drop_box => [:index, :show, :download]
		permission :manage_dropbox_documents, :drop_box => [:new, :edit, :destroy, :destroy_attachment, :synchronize, :synchronize_document, :import, :prepare_import, :add_attachment]
	end
	
    raise 'json library not installed' unless defined?(JSON)
    raise 'multipart-post library not installed' unless defined?(Net::HTTP::Post::Multipart)
    raise 'URI library not installed' unless defined?(URI)
    raise 'oauth library not installed' unless defined?(OAuth)

end
