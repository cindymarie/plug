# -*- encoding: binary -*-
require 'rack/utils'
module Rack
  module Utils
    module Multipart
      def self.parse_multipart(env)
        unless env['CONTENT_TYPE'] =~
            %r|\Amultipart/.*boundary=\"?([^\";,]+)\"?|n
          nil
        else
          boundary = "--#{$1}"

          params = {}
          buf = ""
          content_length = env['CONTENT_LENGTH'].to_i
          input = env['rack.input']
          input.rewind

          boundary_size = Utils.bytesize(boundary) + EOL.size
          bufsize = 16384

          content_length -= boundary_size

          read_buffer = ''

          status = input.read(boundary_size, read_buffer)
          raise EOFError, "bad content body"  unless status == boundary + EOL

          rx = /(?:#{EOL})?#{Regexp.quote boundary}(#{EOL}|--)/n

          loop {
            head = nil
            body = ''
            filename = content_type = name = nil

            until head && buf =~ rx
              if !head && i = buf.index(EOL+EOL)
                head = buf.slice!(0, i+2) # First \r\n
                buf.slice!(0, 2)          # Second \r\n

                token = /[^\s()<>,;:\\"\/\[\]?=]+/
                condisp = /Content-Disposition:\s*#{token}\s*/i
                dispparm = /;\s*(#{token})=("(?:\\"|[^"])*"|#{token})*/

                rfc2183 = /^#{condisp}(#{dispparm})+$/i
                broken_quoted = /^#{condisp}.*;\sfilename="(.*?)"(?:\s*$|\s*;\s*#{token}=)/i
                broken_unquoted = /^#{condisp}.*;\sfilename=(#{token})/i

                if head =~ rfc2183
                  filename = Hash[head.scan(dispparm)]['filename']
                  filename = $1 if filename and filename =~ /^"(.*)"$/
                elsif head =~ broken_quoted
                  filename = $1
                elsif head =~ broken_unquoted
                  filename = $1
                end

                if filename && filename !~ /\\[^\\"]/
                  filename = Utils.unescape(filename).gsub(/\\(.)/, '\1')
                end

                content_type = head[/Content-Type: (.*)#{EOL}/ni, 1]
                name = head[/Content-Disposition:.*\s+name="?([^\";]*)"?/ni, 1] || head[/Content-ID:\s*([^#{EOL}]*)/ni, 1]

                if filename
                  body = Tempfile.new("RackMultipart")
                  body.binmode  if body.respond_to?(:binmode)
                end

                next
              end

              # Save the read body part.
              if head && (boundary_size+4 < buf.size)
                body << buf.slice!(0, buf.size - (boundary_size+4))
              end

              c = input.read(bufsize < content_length ? bufsize : content_length, read_buffer)
              raise EOFError, "bad content body"  if c.nil? || c.empty?
              buf << c
              content_length -= c.size
            end

            # Save the rest.
            if i = buf.index(rx)
              body << buf.slice!(0, i)
              buf.slice!(0, boundary_size+2)

              content_length = -1  if $1 == "--"
            end

            if filename == ""
              # filename is blank which means no file has been selected
              data = nil
            elsif filename
              body.rewind

              # Take the basename of the upload's original filename.
              # This handles the full Windows paths given by Internet Explorer
              # (and perhaps other broken user agents) without affecting
              # those which give the lone filename.
              filename = filename.split(/[\/\\]/).last

              data = {:filename => filename, :type => content_type,
                      :name => name, :tempfile => body, :head => head}
            # elsif !filename && content_type
            #   body.rewind
            # 
            #   # Generic multipart cases, not coming from a form
            #   data = {:type => content_type,
            #           :name => name, :tempfile => body, :head => head}
            else
              data = body
            end

            Utils.normalize_params(params, name, data) unless data.nil?

            # break if we're at the end of a buffer, but not if it is the end of a field
            break if (buf.empty? && $1 != EOL) || content_length == -1
          }

          input.rewind

          params
        end
      end
    end
  end
end