# Encoding: UTF-8
#	Written by: Zuinq Studio
#	Email: info@zuinqstudio.com 
#	Web: http://www.zuinqstudio.com 

# This work is licensed under a Creative Commons Attribution 3.0 License.
# [ http://creativecommons.org/licenses/by/3.0/ ]

# This means you may use it for any purpose, and make any changes you like.
# All we ask is that you include a link back to our page in your credits.

# Looking forward your comments and suggestions! clientes@signo-net.com

require 'rubygems'
require 'shoulda'
require 'pp'
require_dependency 'dropbox/lib/dropbox_sdk'


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
			begin 
				@client.file_create_folder(self.path_archivo)
				logger.debug("****** Creada la carpeta: " + self.path_archivo)
			rescue DropboxError
				logger.debug("****** La carpeta ya existe: " + self.path_archivo)
			end

			logger.debug("****** Enviando fichero...")
			enviado_archivo = @client.put_file(self.ruta, @temp_file)
			if enviado_archivo
				logger.debug("****** Enviado fichero!!!")
			else
				raise DropboxException.new(), "No se ha podido enviar el archivo a DropBox" + self.ruta
			end
		end
    end
  end
  
  def before_destroy
	logger.debug("****** Eliminando documento de DropBox: " + self.ruta)
    if self.ruta != "" && self.path_archivo && self.nombre_archivo
		conectado = dropbox_connect()
		if conectado
			logger.debug("****** Eliminando fichero...")
			begin
				@client.file_delete(self.ruta)
				logger.debug("****** Eliminado fichero!!!")
			rescue DropboxError
				#raise DropboxException.new(), "No se ha podido eliminar el archivo de DropBox" + self.ruta
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
		fichero = @client.get_file(self.ruta)
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
		begin
			movido_archivo = @client.file_move(from , to)
			if movido_archivo
				logger.debug("****** Movido fichero!!!")
				#Actualizamos la ruta del fichero
				self.ruta = to;
			end
		rescue DropboxError
			error = true
		end
	else
		error = true
	end
	if error
		raise DropboxException.new(), "No se ha podido recuperar mover el archivo: " + from 
	end
  end
  
  def update_path(new_path)
    documentName = substring_after_last(self.ruta, "/")
    if (new_path.end_with?"/")
      self.ruta = new_path + documentName
    else
      self.ruta = new_path + "/" + documentName
    end
    self.save
  end
   
  def substring_after_last(cadena, separador) 
    lastIndex = cadena.rindex(separador)
    if (lastIndex != nil)
      return cadena[lastIndex + 1, cadena.length - 1]
    else
      return ""
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
					    subject = l(:asunto_documento_add, :autor => User.current, :proyecto => project.name)
					    mensaje = l(:mensaje_documento_add, :autor => User.current, :documento => nombre_archivo, :proyecto => project.name)
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

        # Check if user has no dropbox session...re-direct them to authorize
        return redirect_to(:action => 'authorize') unless Setting.plugin_redmine_drop_box[:dropbox_session]

		begin
	        @session = DropboxSession.deserialize(Setting.plugin_redmine_drop_box[:dropbox_session])
	        @client = DropboxClient.new(@session, ACCESS_TYPE) #raise an exception if session not authorized
	        @info = @client.account_info # look up account information
		rescue OAuth::Unauthorized
			raise DropboxException.new(), "No se ha podido conectar a DropBox. Usuario/password incorrecto/s"
		end
	end
  end

  
 end
