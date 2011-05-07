# Encoding: UTF-8
#	Written by: Signo-Net
#	Email: clientes@signo-net.com 
#	Web: http://www.signo-net.com 

# This work is licensed under a Creative Commons Attribution 3.0 License.
# [ http://creativecommons.org/licenses/by/3.0/ ]

# This means you may use it for any purpose, and make any changes you like.
# All we ask is that you include a link back to our page in your credits.

# Looking forward your comments and suggestions! clientes@signo-net.com

class DropBoxMailer < ActionMailer::Base
   def send_new_document(recipients, subject, mensaje)
	  #@from = from
	  @recipients = recipients     
	  @sent_on = Time.now
	  @subject = subject
	  @body = mensaje
      @content_type = "text/html"
   end
end  

class DropBoxController < ApplicationController
  default_search_scope :documents
  before_filter :find_project, :only => [:index, :new, :synchronize, :import]
  before_filter :find_document, :only => [:show, :destroy, :edit, :add_attachment, :synchronize_document]
  before_filter :find_attachment, :only => [:destroy_attachment, :download_attachment]
  
  helper :attachments

  unloadable

  def index
    @sort_by = %w(category date title author).include?(params[:sort_by]) ? params[:sort_by] : 'category'
	@documents = DropboxDocument.find :all, :conditions => ["project_id=" + @project.id.to_s]

	case @sort_by
	    when 'date'
	      @grouped = @documents.group_by {|d| d.created_on.to_date }
	    when 'title'
	      @grouped = @documents.group_by {|d| d.title.first.upcase}
	    when 'author'
	      @grouped = @documents.group_by {|d| d.author.name.upcase}
	    else
	      @grouped = @documents.group_by(&:category)
    end
    @document = @project.documents.build
    render :layout => false if request.xhr?
  end
  
  def new
   @document = DropboxDocument.new(params[:document])
   @document.author = User.current
   @document.project_id = @project.id
   #Tenemos que comprobar que no exista ya esa ruta de fichero en dropbox
   @document.ruta = DropboxDocument.ruta_categoria_documento(@document.project, @document.category, @document)
   if DropboxDocument.check_repetido(@document)
	  flash[:warning] = l(:documento_repetido)
	  redirect_to :action => 'index', :project_id => @project
   else
	   #Guardamos
	   if request.post? and @document.save	
	      attachments = DropboxAttachment.attach_files(@project, @document, params[:attachments])
	      render_attachment_warning_if_needed(@document)
		  
		  attachments[:warnings].each{|warning|
			flash[:warning]=warning
		  }
		  
		  subject = l(:asunto_documento_add, :author => User.current, :proyecto => @project.name)
		  mensaje = l(:mensaje_documento_add, :author => User.current, :documento => @document.title, :proyecto => @project.name)
		  DropBoxMailer::deliver_send_new_document(@project.recipients, subject, mensaje) if Setting.notified_events.include?('document_added')
	      
		  flash[:notice] = l(:notice_successful_create)
	      redirect_to :action => 'index', :project_id => @project
	    end
   end
  end
  
  def show
    @attachments = @document.attachments
  end
  
  def add_attachment
    attachments = DropboxAttachment.attach_files(@project, @document, params[:attachments])
    render_attachment_warning_if_needed(@document)

    #Mailer.deliver_attachments_added(attachments[:files]) if attachments.present? && attachments[:files].present? && Setting.notified_events.include?('document_added')
    redirect_to :action => 'show', :id => @document
  end
  
  def edit
    @categories = DocumentCategory.all
    if request.post?
	  # TENDRIAMOS QUE COMPROBAR SI HEMOS CAMBIADO EL NOMBRE, QUE NO EXISTIERA NADA
	  #Actualizamos el registro
	  if @document.update_attributes(params[:document])
		  #Muestro el aviso
	      flash[:notice] = l(:notice_successful_update)
	      redirect_to :action => 'show', :id => @document
	  end
    end
  end

  def destroy
	begin
		if @document.destroy
			flash[:notice] = l(:notice_successful_delete)
			redirect_to :action => 'index', :project_id => @project
		end
	rescue Errno::ETIMEDOUT
		flash[:warning]=l(:error_conexion_dropbox)
	rescue DropboxException
		flash[:warning]=l(:error_conexion_dropbox)
	end
  end
  
  def download_attachment
	begin
		fichero = @attachment.dropbox_file
		filename = @attachment.nombre_archivo
		send_data(fichero, :type=> @attachment.content_type, :filename =>filename, :disposition =>'attachment')
	rescue Errno::ETIMEDOUT
		flash[:warning]=l(:error_conexion_dropbox)
		redirect_to  :action => 'show', :id => @document
	rescue 
		flash[:warning]=l(:error_fichero_no_enco_dropbox)
		redirect_to  :action => 'show', :id => @document
	end
  end

  def destroy_attachment
	begin
		attachment = DropboxAttachment.find(params[:id])
		if attachment.destroy
			flash[:notice] = l(:notice_successful_delete)
			redirect_to  :action => 'show', :id => @document
		end
	rescue Errno::ETIMEDOUT
		flash[:warning]=l(:error_conexion_dropbox)
	rescue DropboxException
		flash[:warning]=l(:error_conexion_dropbox)
	end
  end
  
  def synchronize
	@elementos = {}
	categorias = DocumentCategory.find :all
	doc = DropboxDocument.new()
	total_a_actualizar = 0
	
	categorias.each {|categoria|
		begin
			#Tenemos que recuperar de dropbox por cada categoria, los ficheros que hay
			i = 0
			path_categoria = DropboxDocument.ruta_categoria(@project, categoria);
			metadatos = doc.dropbox_metadatos(path_categoria)
			sql_in = "";
			documentos_dropbox = []
			#Con los ficheros recuperados comprobamos los que tenemos, los que se han borrado y los nuevos
			if metadatos["contents"] != nil
				metadatos["contents"].each {|fichero|
					path = fichero["path"] + "/"
					documentos_dropbox[i] = {"P" => path, "S" => fichero["bytes"]}
					if sql_in != ""
						sql_in += "','"
					end
					sql_in += path
					i = i + 1
				}
			end

			#Los documentos eliminados de dropbox se puede hacer con un sql
			eliminados = DropboxDocument.find :all, :conditions =>["project_id= ? and category_id= ? and ruta not in('" + sql_in + "')", @project.id.to_s , categoria.id.to_s]
			#Los documentos añadidos a dropbox hay que hacerlo uno a uno
			i = 0
			nuevos = []
			documentos_dropbox.each {|dropbox|
				existe = DropboxDocument.find(:first, :conditions =>["ruta= ?", dropbox["P"]])
				if !existe
					nuevos[i] = {"P" => File.basename(dropbox["P"]), "S" => dropbox["S"]}
					i = i + 1
				end
			}
			@elementos[categoria] = {"E"=> eliminados, "N"=> nuevos}
			total_a_actualizar += nuevos.length + eliminados.length
			
		rescue Errno::ETIMEDOUT
			flash[:warning]=l(:error_conexion_dropbox)
		rescue DropboxException
			flash[:warning]=l(:error_conexion_dropbox)
		end
	}

	if total_a_actualizar == 0
		flash[:warning]=l(:label_no_enco_ficheros_sincronizar)
		redirect_to  :action => 'index', :project_id => @project
	end
  end
  
  def import
    if request.post?
	  categoria = DocumentCategory.find(params[:categoria])
	  path_archivo = DropboxDocument.ruta_categoria(@project, categoria) + "/";
	  nombre_archivo = DropboxAttachment.sanitize_filename(params[:document][:title])
      @document = DropboxDocument.new(params[:document])
      @document.author = User.current
	  @document.category_id = categoria.id
	  @document.project_id = @project.id
	  @document.ruta = path_archivo + nombre_archivo;
	  #Si el nombre del archivo es diferente al original, tenemos que renombrarlo en el dropbox
	  if params[:nuevo] != nombre_archivo	
		@document.dropbox_move(path_archivo + params[:nuevo], path_archivo + nombre_archivo)
	  end

	  if @document.save
		  #Tenemos que sincronizar todos los archivos de este documento
			begin
				#Tenemos que recuperar de dropbox por cada categoria, los ficheros que hay
				metadatos = @document.dropbox_metadatos(@document.ruta)
				#Con los ficheros recuperados comprobamos los que tenemos, los que se han borrado y los nuevos
				if metadatos["contents"] != nil
					metadatos["contents"].each {|fichero|
						if fichero["bytes"] > 0
						    attachment = DropboxAttachment.new()
							attachment.author = User.current
							attachment.description = ""
						    attachment.dropbox_document_id = @document.id
						    attachment.ruta = fichero["path"];
							attachment.content_type = Redmine::MimeType.of(File.basename(attachment.ruta))
							attachment.filesize = fichero["bytes"]
							attachment.save
						end
					}
				end
				
			rescue Errno::ETIMEDOUT
				flash[:warning]=l(:error_conexion_dropbox)
			rescue DropboxException
				flash[:warning]=l(:error_conexion_dropbox)
			end
		  #Muestro el aviso
	      flash[:notice] = l(:notice_successful_create)
	      redirect_to :action => 'synchronize', :project_id => @project
	  end
    end
  end

  def synchronize_document
	begin
		#Tenemos que recuperar de dropbox por cada categoria, los ficheros que hay
		categoria = DocumentCategory.find(@document.category_id)
		path_categoria = DropboxDocument.ruta_categoria_documento(@project, categoria, @document);
		metadatos = @document.dropbox_metadatos(path_categoria)
		sql_in = "";
		documentos_dropbox = []
		#Con los ficheros recuperados comprobamos los que tenemos, los que se han borrado y los nuevos
		if metadatos["contents"] != nil
			metadatos["contents"].each {|fichero|
				documentos_dropbox << {"P" => fichero["path"], "S" => fichero["bytes"]}
				if sql_in != ""
					sql_in += "','"
				end
				sql_in += fichero["path"]
			}
		end
		#Los documentos eliminados de dropbox se puede hacer con un sql
		eliminados = 0
		para_eliminar = DropboxAttachment.find :all, :conditions =>["dropbox_document_id= ? and ruta not in('" + sql_in + "')", @document.id.to_s]
		para_eliminar.each {|doc|
			if doc.destroy
			  eliminados = eliminados + 1
			end
		}
		
		#Los documentos añadidos a dropbox hay que hacerlo uno a uno
		anadidos = 0
		documentos_dropbox.each {|dropbox|
			existe = DropboxAttachment.find(:first, :conditions =>["ruta= ?", dropbox["P"]])
			if !existe && dropbox["S"] > 0
				attachment = DropboxAttachment.new()
				attachment.author = User.current
				attachment.description = ""
				attachment.dropbox_document_id = @document.id
				attachment.ruta = dropbox["P"];
				attachment.content_type = Redmine::MimeType.of(File.basename(attachment.ruta))
				attachment.filesize = dropbox["S"]
				if attachment.save
				  anadidos = anadidos + 1
				end
			end
		}

		flash[:notice]=l(:documento_sincronizado, :anadidos => anadidos, :eliminados => eliminados)
		redirect_to  :action => 'show', :id => @document

	rescue Errno::ETIMEDOUT
		flash[:warning]=l(:error_conexion_dropbox)
	rescue DropboxException
		flash[:warning]=l(:error_conexion_dropbox)
	end
  end
 
  private
     
  def find_project
	@project = Project.find(params[:project_id])
	rescue ActiveRecord::RecordNotFound
		render_404
  end
  
  def find_document
     @document = DropboxDocument.find(params[:id])
     @project = Project.find(@document.project_id)     
  rescue ActiveRecord::RecordNotFound
     render_404
  end
  
  def find_attachment
     @attachment = DropboxAttachment.find(params[:id])
     @document = DropboxDocument.find(@attachment.dropbox_document_id)
     @project = Project.find(@document.project_id)     
  rescue ActiveRecord::RecordNotFound
     render_404
  end

  
end
