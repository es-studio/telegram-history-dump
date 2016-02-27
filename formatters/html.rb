require_relative 'lib/formatter_base'
require 'cgi' # For HTML encoding
require 'uri' # For URL encoding

class HtmlFormatter < FormatterBase

  NAME = 'html'

  def start_backup(dialogs)
    FileUtils.remove_dir(output_dir, true)
    FileUtils.mkdir_p(output_dir)
    FileUtils.cp('formatters/html-data/telegram-history-dump.css', output_dir)

    @html_template_index = File.read('formatters/html-data/index.template')
    @html_template_header = File.read('formatters/html-data/dialog-header.template')
    @html_template_footer = File.read('formatters/html-data/dialog-footer.template')

    dialog_list_html = ''
    dialogs.each do |dialog|
      safe_name = get_safe_name(dialog['print_name'])
      html_safe_url = CGI::escapeHTML(URI.escape(safe_name))
      if dialog['type'] != 'user'
        dialog_rendering = '<span class="icon img-group"></span>'
      else
        dialog_rendering = '<span class="icon img-single-user"></span>'
      end
      dialog_list_html += "<div class='dialog msg %s'>#{dialog_rendering} <a href='%s-0.html'>%s</a></div>" % [('out' if dialog['type'] == 'user'), html_safe_url, CGI::escapeHTML(dialog['print_name'])]
    end
    index_file = File.join(output_dir, 'index.html')
    File.open(index_file, 'w:UTF-8') do |stream|
      stream.puts(@html_template_index % dialog_list_html)
    end
  end

  def format_dialog(dialog, messages)
    if dialog['type'] != 'user'
      dialog_title = 'Group chat: %s' % CGI::escapeHTML(dialog['print_name'])
    else
      dialog_title = 'Chat with %s' % CGI::escapeHTML(dialog['print_name'])
    end
    safe_name = get_safe_name(dialog['print_name'])
    current_filename = File.join(output_dir, safe_name + '-0.html')
    backup_file = File.open(current_filename, 'w:UTF-8')
    backup_file.puts(@html_template_header % [CGI::escapeHTML(dialog['print_name']), dialog_title])

    message_count = 0
    page_count = 0
    messages.reverse_each do |msg|
      if not msg['out'] and dialog['type'] != 'user'
        # If this is an incoming message in a group chat, display the author
        author = '<div class=author>%s:</div>'% get_full_name(msg['from'])
      else
        author = ''
      end

      date = Time.at(msg['date'])
      if $config['formatters']['html']['use_utc_time']
        date = "#{date.utc} UTC"
      end

      msg_body = ''
      if msg['text']
        msg_body = replace_urls(msg['text']).gsub("\n", '<br>')
        if msg['media'] and msg['media']['type'] == 'webpage' and msg['media']['description']
          # The webpage URL is already included in the message, only need to display the title here.
          # Note that there are messages with msg[text], msg[media] and msg[media][type]=webpage, but
          # without either msg[media][description] or msg[media][title] or both...
          # I think they are to indicate an inline URL, but it doesn't give the url so we have to figure that
          # out for ourselves, and there are also messages that have no media tag but still contain a clickable url.
          title = msg['media']['title']
          title = "<b>%s</b>" % CGI::escapeHTML(title) if title.to_s != ''
          description = msg['media']['description']
          description = "<br>%s" % CGI::escapeHTML(description) if description.to_s != ''
          if title.to_s != '' and description.to_s != ''
            title += '<br>'
          end
          msg_body += '<div class="webpage">%s%s</div>' % [title, description]
        end
        author += ' ' if author != '' # In text messages (unlike media), author is followed by a space, not a new line
      elsif msg['media'] and msg['media']['file']
        relative_url = URI.escape(File.join("../../media", safe_name, File.basename(msg['media']['file'])))
        extension = File.extname(msg['media']['file'])
        if msg['media']['type'] == 'photo' or ['png', 'jpg', 'gif', 'svg', 'jpeg', 'bmp', 'webp'].include? extension[1..-1]
          # Note: webp is almost certainly a sticker; special support for those is to do (although the need is
          # questionable as they are inlined already).
          msg_body = "<a target='_blank' href='#{relative_url}'><img src='#{relative_url}'></a>"
          if msg['media']['caption']
            msg_body += '<br>' + msg['media']['caption']
          end
        else
          if msg['media']['type'] == 'audio' or ['mp3', 'wav', 'ogg'].include? extension[1..-1]
            filetype = 'audio'
          elsif msg['media']['type'] == 'video' or ['mp4', 'mov', '3gp', 'avi', 'webm'].include? extension[1..-1]
            filetype = 'video'
          else
            # documents
            msg_body = "<a href='#{relative_url}'>Download #{extension} file</a>"
          end
          if filetype == 'audio' or filetype == 'video'
            msg_body = "<#{filetype} src='#{relative_url}' controls>Your browser does not support inline playback.</#{filetype}><br><a href='#{relative_url}'>Download #{filetype}</a>"
          end
        end
        author += '<br>' if author != '' # In file messages (unlike text messages), author is followed by a new line
      elsif msg['media'] and msg['media']['type'] == 'geo'
        lat = msg['media']['latitude'].to_s
        lon = msg['media']['longitude'].to_s
        msg_body = "<div class=geo>Geo location: <a target='_blank' href='https://www.openstreetmap.org/?mlat=#{lat}&mlon=#{lon}#map=15/#{lat}/#{lon}'>(#{lat[0..8]},#{lon[0..8]})</a></div>"
      elsif msg['media'] and msg['media']['type'] == 'contact'
        phone = msg['media']['phone']
        first = msg['media']['first_name']
        last = msg['media']['last_name']
        msg_body = "<div class=contact>Contact: #{first} <!--first-last-->#{last}, +#{phone}</div>"
      elsif msg['event'] == 'service' or msg['service']
        if get_full_name(msg['from']) != '' # Some messages have no properly filled 'from'
          text = CGI::escapeHTML(get_full_name(msg['from']))
        else
          text = '(Unknown user)'
        end
        text += ' '
        if msg['action']['type'] == 'chat_add_user'
          text += "added %s" % CGI::escapeHTML(get_full_name(msg['action']['user']))
        elsif msg['action']['type'] == 'chat_rename'
          text += "changed group name to &laquo;%s&raquo;" % CGI::escapeHTML(msg['action']['title'])
        elsif msg['action']['type'] == 'chat_change_photo'
          text += "updated group photo"
        elsif msg['action']['type'] == 'chat_created'
          text += "created group &laquo;%s&raquo;" % CGI::escapeHTML(msg['action']['title'])
        elsif msg['action']['type'] == 'chat_del_user'
          text += "removed %s" % CGI::escapeHTML(get_full_name(msg['action']['user']))
        else
            text += CGI::escapeHTML(msg['action'].to_s)
        end
        backup_file.puts("<div class='msg-service' title='#{date}'><div class=inner>#{text}</div></div>")
      end
      if msg_body != ''
        in_out = (msg['out'] ? 'out' : 'in')
        backup_file.puts("<div class='msg #{in_out}' title='#{date}'>#{author}#{msg_body}</div>")
      end

      message_count += 1
      messages_per_page = $config['formatters']['html']['paginate']
      if messages_per_page and messages_per_page > 0 and message_count > messages_per_page
        # We reached our message limit on this page; paginate!
        # Is there a previous page? If yes, link to it.
        navigation = ''
        if page_count > 0
          navigation += '<a class=prevpage href="%s-%s.html">Previous page</a>' % [CGI::escapeHTML(URI.escape(safe_name)), page_count]
        end

        page_count += 1
        message_count = 0

        # Link to the next page and end the file
        current_filename = File.join(output_dir, "%s-%s.html" % [CGI::escapeHTML(URI.escape(safe_name)), page_count])
        navigation += '<a class=nextpage href="%s">Next page</a>' % File.basename(current_filename)
        backup_file.puts(@html_template_footer % navigation)
        backup_file.close()

        # Open a new file and write the header again
        backup_file = File.open(current_filename, 'w:UTF-8')
        backup_file.puts(@html_template_header % [CGI::escapeHTML(dialog['print_name']), dialog_title + (' - page %i' % (page_count + 1) if page_count > 0)])
      end
    end
    backup_file.puts(@html_template_footer % '')
    backup_file.close()
  end

  def end_backup
    $log.info("HTML export finished, see: output/formatted/html/index.html")
  end

  def replace_urls(text)
    # This function does not recognize geo: 'urls', which is too bad, but sort of by
    # design. They do not look like URLs with that comma in there and I did not want
    # to get into the business of keeping track of every arcane format out there.

    # This function returns HTML-encoded text with all identifiable URLs made linkable.
    # The reason it also does HTML encoding is because it can't be done afterwards (that
    # would escape the a-href tags) and if it would require the text to be escaped
    # beforehand then it might as well do it by itself.

    # We don't use Ruby's URI.extract because it matches only URLs that include
    # a protocol. Telegram also recognizes URLs like example.com or
    # example.com/search?q=x, so we will try to replicate that behavior at the trade off
    # of some false positives.

    # The function also replaces @usernames and email addresses. Regarding the latter,
    # at least it makes a reasonable attempt.

    # The regex looks, case-insensitive, for: an optional protocol, then an optional
    # user:password part followed by an @-sign, then example.gtld, optionally a port, and
    # optionally /something?query&morequery of any length and containing any character,
    # until a space character appears. It should have some support for IDN domains as
    # well, but it's almost certainly not perfect if you try something beyond basic
    # accents or circumflexes or something, and even then.

    # TODO: IP addresses. IPv6 addresses. I completely forgot about those.

    urls = text.scan(/(^|\s|<)(([a-zA-Z]{1,25}:)?([^@\s]{1,200}@)?(\/\/)?([a-zA-Z][a-zA-Z0-9-]{0,63}\.){0,125}[a-zA-Z][a-zA-Z0-9-]{0,63}\.([a-zA-Z]{2,63}|xn--[a-zA-Z0-9]{1,60})(:[1-9][0-9]{0,4})?(\/[!-~]*)?(\s|>|$|\)|\.))/)

    text = CGI::escapeHTML(text)

    urls.each do |url|
      url = url[1]
      escaped_url = CGI::escapeHTML(url)

      if text.index(escaped_url) == nil
        # If there are duplicate URLs, we might already have replaced it.
        next
      end

      # The last character is a dot followed by a space or end of message, the person probably just ended the sentence.
      at_end = (text.index(escaped_url) + url.length) == text.length
      if url[-2..-1] =~ /\.\s/
        url = url[0..-3]
      elsif url[-1] == '.' and at_end
        url = url[0..-2]
      end

      # The last character is a ), unless the URL also contains a ( or the text
      # message contains no (, let's assume the URL was between parenthesis
      if (url.index('(') == nil and text.gsub(escaped_url, '').index('(') != nil)
        if url[-2..-1] =~ /\)\s/
          url = url[0..-3]
        elsif url[-1] == ')' and at_end
          url = url[0..-2]
        end
      end

      if url[-1] =~ /\s/ # Remove trailing whitespace, if any
        url = url[0..-2]
      end

      # Email addresses and URLs are still fairly often enclosed in 
      # <angle brackets>. Catch this.
      if url[0] == '<'
        url = url[1..-1]
      end
      if url[-1] == '>'
        url = url[0..-2]
      end

      # If there is no protocol part, check whether it's an email
      # address. Otherwise default to http.
      if url[0..26].index(':') == nil
        if url.index('@') != nil
          new_url = "mailto:#{url}"
        else
          new_url = "http://#{url}"
        end
      else
        new_url = url
      end

      # No URI.escape here because it would replace the hash sign
      escaped_url = CGI::escapeHTML(url)
      new_escaped_url = CGI::escapeHTML(new_url)
      text = text.gsub(escaped_url, "<a target='_blank' href='#{new_escaped_url}'>#{escaped_url}</a>")
    end

    usernames = text.scan(/(@[a-zA-Z0-9_]{5,32})([^a-zA-Z0-9_]|$)/)
    usernames.each do |username|
      username = username[0]

      # Check whether this username is part of a URL, in which case it's probably part of an
      # email address or something like ftp://user:pass@example.net.
      should_skip = false
      urls.each do |url|
        url = url[1]
        if url.index(username) != nil
          should_skip = true
          break
        end
      end

      next if should_skip

      if text.index(username) == nil
        # If there are duplicate URLs, we might already have replaced it.
        next
      end

      text = text.gsub(username, "<a target='_blank' href='https://telegram.im/#{username[1..-1]}'>#{username}</a>")
    end

    return text
  end

end

