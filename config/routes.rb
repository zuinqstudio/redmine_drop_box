# Encoding: UTF-8
#	Written by: Signo-Net
#	Email: clientes@signo-net.com 
#	Web: http://www.signo-net.com 

# This work is licensed under a Creative Commons Attribution 3.0 License.
# [ http://creativecommons.org/licenses/by/3.0/ ]

# This means you may use it for any purpose, and make any changes you like.
# All we ask is that you include a link back to our page in your credits.

# Looking forward your comments and suggestions! clientes@signo-net.com

ActionController::Routing::Routes.draw do |map|
   map.connect 'projects/:project_id/dropbox/:action', :controller => 'drop_box'
end


