# Encoding: UTF-8
#	Written by: Signo-Net
#	Email: clientes@signo-net.com 
#	Web: http://www.signo-net.com 

# This work is licensed under a Creative Commons Attribution 3.0 License.
# [ http://creativecommons.org/licenses/by/3.0/ ]

# This means you may use it for any purpose, and make any changes you like.
# All we ask is that you include a link back to our page in your credits.

# Looking forward your comments and suggestions! clientes@signo-net.com

require 'rubygems'
require 'shoulda'
require 'pp'
require_dependency 'dropbox/lib/dropbox'
require_dependency 'dropbox/test/util'


class DropboxException < RuntimeError
  def initialize
  end
end

class DropboxAttachment < ActiveRecord::Base
  unloadable
  
  belongs_to :document, :class_name => "DropboxDocument", :foreign_key => "dropbox_document_id"
  belongs_to :author, :class_name => "User", :foreign_key => "author_id"

  acts_as_activity_provider :type => 'documents',
                            :permission => :view_dropbox_documents,
                            :author_key => :author_id,
                            :find_options => {:select => "#{DropboxAttachment.table_name}.*", 
                                              :joins => "LEFT JOIN #{DropboxDocument.table_name} ON #{DropboxDocument.table_name}.id = #{DropboxAttachment.table_name}.dropbox_document_id " +
                                                        "LEFT JOIN #{Project.table_name} ON #{DropboxDocument.table_name}.project_id = #{Project.table_name}.id"}


  validates_presence_of :author
 
  def before_create
	logger.debug("****** Creando nuevo documento")
	self.created_on = Time.now
	self.updated_on = Time.now
	logger.debug("****** Enviando documento a DropBox")
    if @temp_file && (@temp_file.size > 0) && self.path_archivo && self.nombre_archivo
		logger.debug("****** Guardando documento en: " + self.ruta)
		conectado = dropbox_connect()
		if conectado
			creada_carpeta = @client.file_create_folder(@conf['root'], self.path_archivo)
			if creada_carpeta
				logger.debug("****** Creada la carpeta: " + self.path_archivo)
				logger.debug("****** Enviando fichero...")
				enviado_archivo = @client.put_file(@conf['root'], self.path_archivo, self.nombre_archivo, @temp_file)
				if enviado_archivo
					logger.debug("****** Enviado fichero!!!")
				else
					raise DropboxException.new(), "No se ha podido enviar el archivo a DropBox" + self.ruta
				end
			else
				raise DropboxException.new(), "No se ha podido crear la carpeta en DropBox" + self.path_archivo
			end
		end
    end
  end
  
  def before_update
	logger.debug("****** Actualizando documento")
	self.updated_on = Time.now
    if not @temp_file.blank?
		logger.debug("****** Se ha enviado un nuevo fichero, borramos el anterior y subimos el nuevo")
		conectado = dropbox_connect()
		if conectado
			logger.debug("****** Eliminando fichero: " + self.ruta)
			eliminado_archivo = @client.file_delete(@conf['root'], self.ruta)
			if eliminado_archivo
				logger.debug("****** Eliminado fichero!!!")
				#Comprobamos que no exista ya un fichero con ese nombre en esa carpeta
				path_archivo = DropboxDocument.ruta_categoria_documento(self.documento.project, self.documento.category, self.documento);
				nombre_archivo = DropboxDocument.get_nombre_si_repetido(@temp_file.original_filename, path_archivo, self.documento.project, self.category_id)
				logger.debug("****** Enviando nuevo fichero: " + path_archivo + nombre_archivo)
				enviado_archivo = @client.put_file(@conf['root'], path_archivo, nombre_archivo, @temp_file)
				if enviado_archivo
					logger.debug("****** Enviado fichero!!!")
					#Actualizamos la ruta del fichero
					self.ruta = path_archivo + nombre_archivo;
				else
					raise DropboxException.new(), "No se ha podido enviar el nuevo archivo a DropBox" + self.ruta
				end
				
			else
				raise DropboxException.new(), "No se ha podido eliminar el archivo de DropBox" + self.ruta
			end
		end
	else
		logger.debug("****** No se ha actualizado el fichero")
		#Miramos si ha cambiado la categoria para mover el archivo
		documento_guardado =  DropboxDocument.find(self.id)
		categoria_anterior = documento_guardado.category_id
		if self.category_id != categoria_anterior
			logger.debug("****** Hemos cambiado la categoria del archivo ")
			path_archivo = DropboxDocument.ruta_categoria_documento(self.documento.project, self.documento.category, self.documento);
			nombre_archivo = DropboxDocument.get_nombre_si_repetido(self.nombre_archivo, path_archivo, self.documento.project, self.category_id)
			logger.debug("****** Moviendo fichero de : " + self.ruta + " => " + path_archivo + nombre_archivo)
			conectado = dropbox_connect()
			if conectado
				movido_archivo = @client.file_move(@conf['root'], self.ruta , path_archivo + nombre_archivo)
				if movido_archivo
					logger.debug("****** Enviado fichero!!!")
					#Actualizamos la ruta del fichero
					self.ruta = path_archivo + nombre_archivo;
				end
			else
				raise DropboxException.new(), "No se ha podido eliminar el archivo de DropBox" + self.ruta
			end
		else
			logger.debug("****** No hemos cambiado la categoria del archivo ")
		end
	end
  end
  
  def before_destroy
	logger.debug("****** Eliminando documento de DropBox: " + self.ruta)
    if self.ruta != "" && self.path_archivo && self.nombre_archivo
		conectado = dropbox_connect()
		if conectado
			logger.debug("****** Eliminando fichero...")
			eliminado_archivo = @client.file_delete(@conf['root'], self.ruta)
			if eliminado_archivo
				logger.debug("****** Eliminado fichero!!!")
			else
				raise DropboxException.new(), "No se ha podido eliminar el archivo de DropBox" + self.ruta
			end
		end
    end
  end
  
  def file=(incoming_file)
    unless incoming_file.nil?
      @temp_file = incoming_file
      if @temp_file.size > 0
        self.content_type = @temp_file.content_type.to_s.chomp
        if content_type.blank?
          self.content_type = Redmine::MimeType.of(@temp_file.original_filename)
        end
		self.filesize = @temp_file.size
      end
    end
  end
	
  def file
    return @temp_file
  end

  def path_archivo
	return File.dirname(self.ruta)
  end

  def nombre_archivo
	return File.basename(self.ruta)
  end
  
  def dropbox_file
	conectado = dropbox_connect()
	error = false
	if conectado
		logger.debug("****** Recuperando fichero de DropBox: " + self.ruta)
		fichero = @client.get_file(@conf['root'], self.ruta)
		if fichero
			filename = File.basename(self.ruta)
			logger.debug("****** Fichero recuperado: " + filename)
			return fichero
		else
			error = true
		end
	else
		error = true
	end
	if error
		raise DropboxException.new(), "No se ha podido recuperar el fichero"
	end
  end
  
  def dropbox_move(from, to)
	logger.debug("****** Renombreando fichero de '" + from + "' a '" + to + "'")
	conectado = dropbox_connect()
	error = false
	if conectado
		movido_archivo = @client.file_move(@conf['root'], from , to)
		if movido_archivo
			logger.debug("****** Movido fichero!!!")
			#Actualizamos la ruta del fichero
			self.ruta = to;
		end
	else
		error = true
	end
	if error
		raise DropboxException.new(), "No se ha podido recuperar mover el archivo: " + from 
	end
  end
  
  #Static methods
  def self.validar_nombre_fichero(fichero)
    return validar_nombre_cadena(fichero.original_filename)    
  end
  
  def self.validar_nombre_cadena(cadena)
    valido=true
    noValidosDocumento= ['%','?','&',':',';','|','<','>','/',"\+","\\","\'",'¬','£']
    noValidosAdjunto=   ['*','%','?','&',':',';','|','<','>','/',"\+","\\",'¬','£']
    finalNoValidos= ['.',' ']
  
    if cadena==nil #este caso se da cuando se ha incluido un caracter \ al final del nombre
      valido=false
      flash[:error]=l(:error_caracteres_finales)
      flash.discard
    elsif finalNoValidos.include?(cadena[-1].chr) || noValidosAdjunto.include?(cadena[-1].chr) 
      valido=false 
      flash[:error]=l(:error_caracteres_finales)
      flash.discard
    else
      array=cadena.split("")
      array.each do |p|
        if noValidosAdjunto.include?(p)
          valido=false
          flash[:error]=l(:error_caracteres_finales)
          flash.discard
          break
        end
      end
    end
    return valido
  end
  
  def self.attach_files(project, document, attachments)
    attached = []
	warnings = []
    if attachments && attachments.is_a?(Hash)
      attachments.each_value do |tmp|
        file = tmp['file']
		desc = tmp['description']
        next unless file && file.size > 0
		if file && validar_nombre_fichero(file)
			#Comprobamos el tamaño
			if DropboxAttachment.check_size_reached(file.size)
				warnings << l(:label_filesize_reached, DropboxAttachment.get_max_filesize_mb.to_s)
				redirect_to :action => 'new', :project_id => project
			else
			    attachment = DropboxAttachment.new()
				attachment.author = User.current
				attachment.description = desc
			    attachment.dropbox_document_id = document.id
				attachment.file = file
				#ahora comprobamos que no exista en redmine otro documento con el mismo proyect_id, categoria de documento y titulo
				nombre_archivo = DropboxAttachment.get_nombre_si_repetido(file.original_filename, document.ruta, document)
			    attachment.ruta = document.ruta + nombre_archivo;

				begin
					if attachment.save
					    subject = l(:asunto_documento_add, :author => User.current, :proyecto => project.name)
					    mensaje = l(:mensaje_documento_add, :author => User.current, :documento => nombre_archivo, :proyecto => project.name)
						DropBoxMailer::deliver_send_new_document(project.recipients, subject, mensaje) if Setting.notified_events.include?('document_added')
			            attached << attachment
					else
						document.unsaved_attachments ||= []
						document.unsaved_attachments << attachment
					end
				rescue Errno::ETIMEDOUT
					warnings << l(:error_conexion_dropbox)
				rescue DropboxException
					warnings << l(:error_conexion_dropbox)
				end
			end
		else
			warnings << l(:error_conexion_dropbox)
		end
      end
    end
    {:files => attached, :unsaved => document.unsaved_attachments, :warnings => warnings}
  end
   
  def self.get_nombre_si_repetido(nombre_archivo, path_archivo, document)
	repetido = DropboxAttachment.find(:first, :conditions =>["dropbox_document_id= ? and ruta= ?", document.id.to_s  ,  path_archivo + nombre_archivo])
	if repetido # si hay un documento ya con ese nombre, le meto el timestamp
		nombre_archivo = Time.now.to_i.to_s + "_" + nombre_archivo
	end
	return sanitize_filename(nombre_archivo)
  end

  def self.sanitize_filename(filename)
    filename.strip.tap do |name|
      # NOTE: File.basename doesn't work right with Windows paths on Unix
      # get only the filename, not the whole path
      name.sub! /\A.*(\\|\/)/, ''
      # Finally, replace all non alphanumeric, underscore
      # or periods with underscore
      name.gsub! /[^\w\.\-]/, '_'
	  name.gsub! 'á', 'a'
	  name.gsub! 'é', 'e'
	  name.gsub! 'í', 'i'
	  name.gsub! 'ó', 'o'
	  name.gsub! 'ú', 'u'
    end
  end   

  def self.normalizar_cadena(texto)
	temp = texto.downcase.gsub(" ", "_")
	temp = temp.gsub(".", "estoesunpunto")
	temp = temp.mb_chars.normalize(:kd).gsub(/[^x00-\x7F]/n, '').to_s
	temp = temp.gsub("estoesunpunto", ".")
	return temp
  end
   
  def self.get_max_filesize_mb
	return 10
  end
  
  def self.get_max_filesize_bytes
	return (get_max_filesize_mb*1000*1000)
  end
  
  def self.check_size_reached(size)
	return (size > get_max_filesize_bytes)
  end

  private
 
  def dropbox_connect
	if @client
		logger.debug("****** Ya estaba conectando a DropBox... ")
		return true
	else
		logger.debug("****** Conectando a DropBox... ")
		dropbox_config()
		if (@conf && @conf["testing_user"] != "" && @conf["testing_password"] != "")
			begin
				logger.debug("****** Recuperada configuración. Usuario: " + @conf["testing_user"] + " Passw: " + @conf["testing_password"])
				@auth = Authenticator.new(@conf) unless defined?(AUTH)
				login_and_authorize(@auth.get_request_token, @conf)
				@access_token = @auth.get_access_token
				@client = DropboxClient.new(@conf['server'], @conf['content_server'], @conf['port'], @auth)
				logger.debug("****** Conectado a DropBox ")
			rescue OAuth::Unauthorized
				raise DropboxException.new(), "No se ha podido conectar a DropBox. Usuario/password incorrecto/s"
			end
			return true
		else
			logger.debug("****** No se ha podido conectar a DropBox. No está definido usuario y password ")
			raise DropboxException.new(), "No se ha podido conectar a DropBox. No está definido usuario y password"
			return false
		end
	end
  end
  
  def dropbox_config
	@conf = Authenticator.load_config(File.dirname(__FILE__) + "/../../lib/dropbox/config/testing.json")
	@conf["testing_user"] = Setting.plugin_redmine_drop_box["USERNAME"]
	@conf["testing_password"] = Setting.plugin_redmine_drop_box["PASSWORD"]
  end

  
 end
