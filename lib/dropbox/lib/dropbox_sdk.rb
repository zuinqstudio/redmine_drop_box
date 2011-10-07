require 'rubygems'
require 'oauth'
require 'json'
require 'uri'
require 'yaml'

DROPBOX_API_SERVER = "api.dropbox.com"
DROPBOX_API_CONTENT_SERVER = "api-content.dropbox.com"
APP_KEY = "imhmwa7p9sbkvye"
APP_SECRET = "u8j8t8kg3hwjz7t"
ACCESS_TYPE = :dropbox
API_VERSION = 1

# DropboxSession is responsible for holding OAuth information.  It knows how to take your consumer key and secret
# and request an access token, an authorize url, and get an access token.  You just need to pass it to
# DropboxClient after its been authorized.
class DropboxSession
    def initialize(key, secret)
        @consumer_key = key
        @consumer_secret = secret
        @oauth_conf = {
            :site => "https://" + DROPBOX_API_SERVER,
            :scheme => :header,
            :http_method => :post,
            :request_token_url => "/#{API_VERSION}/oauth/request_token",
            :access_token_url => "/#{API_VERSION}/oauth/access_token",
            :authorize_url => "/#{API_VERSION}/oauth/authorize",
        }

        @consumer = OAuth::Consumer.new(@consumer_key, @consumer_secret, @oauth_conf)
        @access_token = nil
        @request_token = nil
    end

    # This gets a request token. Callbacks are excluded, and any arguments provided are passed on
    # to the oauth gem's get_request_token call.
    def get_request_token(*args)
        begin
            @request_token ||= @consumer.get_request_token({:exclude_callback => true}, *args)
        rescue OAuth::Unauthorized => e
            raise DropboxAuthError.new("Could not get request token, unauthorized.  Is your app key and secret correct? #{e}")
        end
    end

    # This returns a URL that your user must visit to grant
    # permissions to this application.
    def get_authorize_url(callback=nil, *args)
        get_request_token(*args)

        url = @request_token.authorize_url
        if callback
            url +=  "&oauth_callback=" + URI.escape(callback)
        end

        "https://www.dropbox.com" + url
    end

    # Clears the access_token
    def clear_access_token
        @access_token = nil
    end

    # Given a saved request token and secret, set this location's token and secret
    # * token - this is the request token
    # * secret - this is the request token secret
    def set_request_token(key, secret)
        @request_token = OAuth::RequestToken.new(@consumer, key, secret)
    end

    # Given a saved access token and secret, you set this Session to use that token and secret
    # * token - this is the access token
    # * secret - this is the access token secret
    def set_access_token(key, secret)
        @access_token = OAuth::AccessToken.from_hash(@consumer, {:oauth_token => key, :oauth_token_secret => secret})
    end

    def check_authorized
        ##this check is applied before the token and secret methods
        raise DropboxError.new('Session does not yet have a request token') unless authorized?
    end

    # Returns the current oauth access or request token.
    def token
        (@access_token || @request_token).token
    end

    # Returns the current oauth access or request token secret.
    def secret
        (@access_token || @request_token).secret
    end

    # Returns the access token. If this DropboxSession doesn't yet have an access_token, it requests one
    # using the request_token generate from your app's token and secret.  This request will fail unless
    # your user has got to the authorize_url and approved your request
    def get_access_token
        if @access_token.nil?
            if @request_token.nil?
                raise DropboxAuthError.new("No request token. You must set this or get an authorize url first.")
            end

            begin
                @access_token = @request_token.get_access_token
            rescue OAuth::Unauthorized => e
                raise DropboxAuthError.new("Could not get access token, unauthorized.  Did you go to authorize_url? #{e}")
            end
        end
        @access_token
    end

    # Returns true if this Session has been authorized and has an access_token.
    def authorized?
        !!@access_token
    end

    # serialize the DropboxSession.
    # At DropboxSession's state is capture in three key/secret pairs.  Consumer, request, and access.
    # This takes the form of an array that is then converted to yaml
    # [consumer_key, consumer_secret, request_token.token, request_token.secret, access_token.token, access_token.secret]
    # access_token is only included if it already exists in the DropboxSesssion
    def serialize
        toreturn = []
        if @access_token
            toreturn.push @access_token.secret, @access_token.token
        end

        get_request_token unless @request_token

        toreturn.push @request_token.secret, @request_token.token
        toreturn.push @consumer_secret, @consumer_key

        toreturn.to_yaml
    end

    # Takes a serialized DropboxSession and returns a new DropboxSession object
    def self.deserialize(ser)
        ser = YAML::load(ser)
        session = DropboxSession.new(ser.pop, ser.pop)
        session.set_request_token(ser.pop, ser.pop)

        if ser.length > 0
            session.set_access_token(ser.pop, ser.pop)
        end
        session
    end
end



# This is the usual error raised on any Dropbox related Errors
class DropboxError < RuntimeError
    attr_accessor :http_response, :error, :user_error
    def initialize(error, http_response=nil, user_error=nil)
        @error = error
        @http_response = http_response
        @user_error = user_error
    end

    def to_s
        return "#{user_error} (#{error})" if user_error
        "#{error}"
    end
end

# This is the error raised on Authentication failures.  Usually this means
# one of three things
# * Your user failed to go to the authorize url and approve your application
# * You set an invalid or expired token and secret on your Session
# * Your user deauthorized the application after you stored a valid token and secret
class DropboxAuthError < DropboxError
end

# This is raised when you call metadata with a hash and that hash matches
# See documentation in metadata function
class DropboxNotModified < DropboxError
end

# This is the Dropbox Client API you'll be working with most often.  You need to give it
# a DropboxSession which has already been authorize, or which it can authorize.
class DropboxClient

    # Initialize a new DropboxClient.  You need to get it a session which either has been authorized. See
    # documentation on DropboxSession for how to authorize it.
    def initialize(session, root="app_folder", locale=nil)
        if not session.authorized?
            begin
                ## attempt to get an access token and authorize the session
                session.get_access_token
            rescue OAuth::Unauthorized => e
                raise DropboxAuthError.new("Could not initialize. Failed to get access token from Session. Error was: #{ e.message }")
                # If this was raised, the user probably didn't go to auth.get_authorize_url
            end
        end

        @root = root.to_s  # If they passed in a symbol, make it a string

        if not ["dropbox","app_folder"].include?(@root)
            raise DropboxError.new("root must be :dropbox or :app_folder")
        end
        if @root == "app_folder"
            #App Folder is the name of the access type, but for historical reasons
            #sandbox is the URL root compontent that indicates this
            @root = "sandbox"
        end

        @locale = locale
        @session = session
        @token = session.get_access_token

        #There's no gurantee that @token is still valid, so be sure to handle any DropboxAuthErrors that can be raised
    end

    # Parse response. You probably shouldn't be calling this directly.  This takes responses from the server
    # and parses them.  It also checks for errors and raises exceptions with the appropriate messages.
    def parse_response(response, raw=false) # :nodoc:
        if response.kind_of?(Net::HTTPServerError)
            raise DropboxError.new("Dropbox Server Error: #{response} - #{response.body}", response)
        elsif response.kind_of?(Net::HTTPUnauthorized)
            raise DropboxAuthError.new(response, "User is not authenticated.")
        elsif not response.kind_of?(Net::HTTPSuccess)
            begin
                d = JSON.parse(response.body)
            rescue
                raise DropboxError.new("Dropbox Server Error: body=#{response.body}", response)
            end
            if d['user_error'] and d['error']
                raise DropboxError.new(d['error'], response, d['user_error'])  #user_error is translated
            elsif d['error']
                raise DropboxError.new(d['error'], response)
            else
                raise DropboxError.new(response.body, response)
            end
        end

        return response.body if raw

        begin
            return JSON.parse(response.body)
        rescue JSON::ParserError
            raise DropboxError.new("Unable to parse JSON response", response)
        end

    end


    # Returns account info in a Hash object
    #
    # For a detailed description of what this call returns, visit:
    # https://www.dropbox.com/developers/docs#account-info
    def account_info()
        response = @token.get build_url("/account/info")
        parse_response(response)
    end

    # Uploads a file to a server.  This uses the HTTP PUT upload method for simplicity
    #
    # Arguments:
    # * to_path: The directory path to upload the file to. If the destination
    #   directory does not yet exist, it will be created.
    # * file_obj: A file-like object to upload. If you would like, you can 
    #   pass a string as file_obj.
    # * overwrite: Whether to overwrite an existing file at the given path. [default is False]
    #   If overwrite is False and a file already exists there, Dropbox
    #   will rename the upload to make sure it doesn't overwrite anything.
    #   You must check the returned metadata to know what this new name is.
    #   This field should only be True if your intent is to potentially
    #   clobber changes to a file that you don't know about.
    # * parent_rev: The rev field from the 'parent' of this upload. [optional]
    #   If your intent is to update the file at the given path, you should
    #   pass the parent_rev parameter set to the rev value from the most recent
    #   metadata you have of the existing file at that path. If the server
    #   has a more recent version of the file at the specified path, it will
    #   automatically rename your uploaded file, spinning off a conflict.
    #   Using this parameter effectively causes the overwrite parameter to be ignored.
    #   The file will always be overwritten if you send the most-recent parent_rev,
    #   and it will never be overwritten you send a less-recent one.
    # Returns:
    # * a Hash containing the metadata of the newly uploaded file.  The file may have a different name if it conflicted.
    #
    # Simple Example
    #  client = DropboxClient(session, "app_folder")
    #  #session is a DropboxSession I've already authorized
    #  client.put_file('/test_file_on_dropbox', open('/tmp/test_file'))
    # This will upload the "/tmp/test_file" from my computer into the root of my App's app folder
    # and call it "test_file_on_dropbox".
    # The file will not overwrite any pre-existing file.
    def put_file(to_path, file_obj, overwrite=false, parent_rev=nil)

        path = "/files_put/#{@root}#{format_path(to_path)}"

        params = {
            'overwrite' => overwrite.to_s
        }

        params['parent_rev'] = parent_rev unless parent_rev.nil?

        response = @token.put(build_url(path, params, content_server=true),
                              file_obj,
                              "Content-Type" => "application/octet-stream")

        parse_response(response)
    end

    # Download a file
    #
    # Args:
    # * from_path: The path to the file to be downloaded
    # * rev: A previous revision value of the file to be downloaded
    #
    # Returns:
    # * The file contents.
    def get_file(from_path, rev=nil)
        params = {}
        params['rev'] = rev.to_s if rev

        path = "/files/#{@root}#{format_path(from_path)}"
        response = @token.get(build_url(path, params, content_server=true))

        parse_response(response, raw=true)
    end

    # Copy a file or folder to a new location.
    #
    # Arguments:
    # * from_path: The path to the file or folder to be copied.
    # * to_path: The destination path of the file or folder to be copied.
    #   This parameter should include the destination filename (e.g.
    #   from_path: '/test.txt', to_path: '/dir/test.txt'). If there's
    #   already a file at the to_path, this copy will be renamed to
    #   be unique.
    #
    # Returns:
    # * A hash with the metadata of the new copy of the file or folder.
    #   For a detailed description of what this call returns, visit:
    #   https://www.dropbox.com/developers/docs#fileops-copy
    def file_copy(from_path, to_path)
        params = {
            "root" => @root,
            "from_path" => format_path(from_path, false),
            "to_path" => format_path(to_path, false),
        }
        response = @token.get(build_url("/fileops/copy", params))
        parse_response(response)
    end

    # Create a folder.
    #
    # Arguments:
    # * path: The path of the new folder.
    #
    # Returns:
    # *  A hash with the metadata of the newly created folder.
    #    For a detailed description of what this call returns, visit:
    #    https://www.dropbox.com/developers/docs#fileops-create-folder
    def file_create_folder(path)
        params = {
            "root" => @root,
            "path" => format_path(path, false),
        }
        response = @token.get(build_url("/fileops/create_folder", params))

        parse_response(response)
    end

    # Deletes a file
    #
    # Arguments:
    # * path: The path of the file to delete
    #
    # Returns:
    # *  A Hash with the metadata of file just deleted.
    #    For a detailed description of what this call returns, visit:
    #    https://www.dropbox.com/developers/docs#fileops-delete
    def file_delete(path)
        params = {
            "root" => @root,
            "path" => format_path(path, false),
        }
        response = @token.get(build_url("/fileops/delete", params))
        parse_response(response)
    end

    # Moves a file
    #
    # Arguments:
    # * from_path: The path of the file to be moved
    # * to_path: The destination path of the file or folder to be moved
    #   If the file or folder already exists, it will be renamed to be unique.
    #
    # Returns:
    # *  A Hash with the metadata of file or folder just moved.
    #    For a detailed description of what this call returns, visit:
    #    https://www.dropbox.com/developers/docs#fileops-delete
    def file_move(from_path, to_path)
        params = {
            "root" => @root,
            "from_path" => format_path(from_path, false),
            "to_path" => format_path(to_path, false),
        }
        response = @token.post(build_url("/fileops/move", params))
        parse_response(response)
    end

    # Retrives metadata for a file or folder
    #
    # Arguments:
    # * path: The path to the file or folder.
    # * list: Whether to list all contained files (only applies when
    #   path refers to a folder).
    # * file_limit: The maximum number of file entries to return within
    #   a folder. If the number of files in the directory exceeds this
    #   limit, an exception is raised. The server will return at max
    #   10,000 files within a folder.
    # * hash: Every directory listing has a hash parameter attached that
    #   can then be passed back into this function later to save on
    #   bandwidth. Rather than returning an unchanged folder's contents, if
    #   the hash matches a DropboxNotModified exception is raised.
    #
    # Returns:
    # * A Hash object with the metadata of the file or folder (and contained files if
    #   appropriate).  For a detailed description of what this call returns, visit:
    #   https://www.dropbox.com/developers/docs#metadata
    def metadata(path, file_limit=10000, list=true, hash=nil)
        params = {
            "file_limit" => file_limit.to_s,
            "list" => list.to_s
        }

        params["hash"] = hash if hash

        response = @token.get build_url("/metadata/#{@root}#{format_path(path)}", params=params)
        if response.kind_of? Net::HTTPRedirection
                raise DropboxNotModified.new("metadata not modified")
        end
        parse_response(response)
    end

    # Search directory for filenames matching query
    #
    # Arguments:
    # * path: The directory to search within
    # * query: The query to search on (3 character minimum)
    # * file_limit: The maximum number of file entries to return/
    #   If the number of files exceeds this
    #   limit, an exception is raised. The server will return at max 10,000
    # * include_deleted: Whether to include deleted files in search results
    #
    # Returns:
    # * A Hash object with a list the metadata of the file or folders matching query
    #   inside path.  For a detailed description of what this call returns, visit:
    #   https://www.dropbox.com/developers/docs#search
    def search(path, query, file_limit=10000, include_deleted=false)

        params = {
            'query' => query,
            'file_limit' => file_limit.to_s,
            'include_deleted' => include_deleted.to_s
        }

        response = @token.get(build_url("/search/#{@root}#{format_path(path)}", params))
        parse_response(response)

    end

    # Retrive revisions of a file
    #
    # Arguments:
    # * path: The file to fetch revisions for. Note that revisions
    #   are not available for folders.
    # * rev_limit: The maximum number of file entries to return within
    #   a folder. The server will return at max 1,000 revisions.
    #
    # Returns:
    # * A Hash object with a list of the metadata of the all the revisions of
    #   all matches files (up to rev_limit entries)
    #   For a detailed description of what this call returns, visit:
    #   https://www.dropbox.com/developers/docs#revisions
    def revisions(path, rev_limit=1000)

        params = {
            'rev_limit' => rev_limit.to_s
        }

        response = @token.get(build_url("/revisions/#{@root}#{format_path(path)}", params))
        parse_response(response)

    end

    # Restore a file to a previous revision.
    #
    # Arguments:
    # * path: The file to restore. Note that folders can't be restored.
    # * rev: A previous rev value of the file to be restored to.
    #
    # Returns:
    # * A Hash object with a list the metadata of the file or folders restored
    #   For a detailed description of what this call returns, visit:
    #   https://www.dropbox.com/developers/docs#search
    def restore(path, rev)
        params = {
            'rev' => rev.to_s
        }

        response = @token.get(build_url("/restore/#{@root}#{format_path(path)}", params))
        parse_response(response)
    end

    # Returns a direct link to a media file
    # All of Dropbox's API methods require OAuth, which may cause problems in
    # situations where an application expects to be able to hit a URL multiple times
    # (for example, a media player seeking around a video file). This method
    # creates a time-limited URL that can be accessed without any authentication.
    #
    # Arguments:
    # * path: The file to stream.
    #
    # Returns:
    # * A Hash object that looks like the following:
    #      {'url': 'https://dl.dropbox.com/0/view/wvxv1fw6on24qw7/file.mov', 'expires': 'Thu, 16 Sep 2011 01:01:25 +0000'}
    def media(path)
        response = @token.get(build_url("/media/#{@root}#{format_path(path)}"))
        parse_response(response)
    end

    # Get a URL to share a media file
    # Shareable links created on Dropbox are time-limited, but don't require any
    # authentication, so they can be given out freely. The time limit should allow
    # at least a day of shareability, though users have the ability to disable
    # a link from their account if they like.
    #
    # Arguments:
    # * path: The file to share.
    #
    # Returns:
    # * A Hash object that looks like the following example:
    #      {'url': 'http://www.dropbox.com/s/m/a2mbDa2', 'expires': 'Thu, 16 Sep 2011 01:01:25 +0000'}
    #   For a detailed description of what this call returns, visit:
    #    https://www.dropbox.com/developers/docs#share
    def shares(path)
        response = @token.get(build_url("/shares/#{@root}#{format_path(path)}"))
        parse_response(response)
    end

    # Download a thumbnail for an image.
    #
    # Arguments:
    # * from_path: The path to the file to be thumbnailed.
    # * size: A string describing the desired thumbnail size. At this time,
    #   'small', 'medium', and 'large' are officially supported sizes
    #   (32x32, 64x64, and 128x128 respectively), though others may
    #   be available. Check https://www.dropbox.com/developers/docs#thumbnails
    #   for more details. [defaults to large]
    # Returns:
    # * The thumbnail data
    def thumbnail(from_path, size='large')
        from_path = format_path(from_path, false)

        raise DropboxError.new("size must be small medium or large. (not '#{size})") unless ['small','medium','large'].include?(size)

        params = {
            "size" => size
        }

        url = build_url("/thumbnails/#{@root}#{from_path}", params, content_server=true)

        response = @token.get(url)
        parse_response(response, raw=true)
    end

    def build_url(url, params=nil, content_server=false) # :nodoc:
        port = 443
        host = content_server ? DROPBOX_API_CONTENT_SERVER : DROPBOX_API_SERVER
        versioned_url = "/#{API_VERSION}#{url}"

        target = URI::Generic.new("https", nil, host, port, nil, versioned_url, nil, nil, nil)

        #add a locale param if we have one
        #initialize a params object is we don't have one
        if @locale
            (params ||= {})['locale']=@locale
        end

        if params
            target.query = params.collect {|k,v|
                URI.escape(k) + "=" + URI.escape(v)
            }.join("&")
        end

        target.to_s
    end
end


#From the oauth spec plus "/".  Slash should not be ecsaped
RESERVED_CHARACTERS = /[^a-zA-Z0-9\-\.\_\~\/]/

def format_path(path, escape=true) # :nodoc:
    path = path.gsub(/\/+/,"/")
    # replace multiple slashes with a single one

    path = path.gsub(/^\/?/,"/")
    # ensure the path starts with a slash

    path.gsub(/\/?$/,"")
    # ensure the path doesn't end with a slash

    return URI.escape(path, RESERVED_CHARACTERS) if escape
    path
end

