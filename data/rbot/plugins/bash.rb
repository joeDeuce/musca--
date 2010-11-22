#-- vim:sw=2:et
#++
#
# :title: bash.org quote retrieval
#
# Author:: Robin Kearney <robin@riviera.org.uk>
# Author:: cs
# Author:: Giuseppe "Oblomov" Bilotta <giuseppe.bilotta@gmail.com>
#
# Copyright:: (C) 2005 Robin Kearney
# Copyright:: (C) 2007 cs, Giuseppe Bilotta
#
# License:: public domain
#
# TODO improve output of quote
# TODO show more than one quote
# TODO allow selection of only quotes with vote > 0

require 'rexml/document'

class ::BashQuote
  attr_accessor :num, :text, :irc_text, :vote

  def initialize(num, text, vote)
    @num = num.to_i
    @text = text
    @vote = vote
    @irc_text = mk_irc_text
  end

  def url
    "http://www.bash.org/?#{@num}"
  end

  def to_s
    "#%d (%d): %s" % [self.num, self.vote, self.irc_text]
  end

  private
  def mk_irc_text
    cur_nick = nil
    last_nick = nil
    text = String.new
    @text.each_line { |l|
      debug "line: #{l.inspect}"
      cur_nick = l.match(/^\s*(&lt;.*?&gt;|\(.*?\)|.*?:)\s/)[1] rescue nil
      debug "nick: #{cur_nick.inspect}; last: #{last_nick.inspect}"
      if cur_nick and cur_nick == last_nick
        text << l.sub(cur_nick,"")
      else
        last_nick = cur_nick.dup if cur_nick
        text << l
      end
    }
    debug text
    # TODO: the gsub of br tags to | should be an ircify_html option
    text.gsub(/(?:<br \/>\s*)+/, ' | ').ircify_html
  end

end

class BashPlugin < Plugin

  Config.register Config::EnumValue.new('bash.access',
    :values => ['xml', 'html'], :default => 'html',
    :desc => "Which method the bot should use to access bash.org quotes: xml files or standard webpages")

  include REXML
  def help(plugin, topic="")
    [
      _("bash => print a random quote from bash.org"),
      _("bash quote_id => print that quote id from bash.org"),
      _("bash search <terms> => print the first bash.org quote matching <terms>"),
      _("bash latest => print the latest quote from bash.org")
    ].join(", ")
  end

  def bash_filter(s)
    # check if we like the location of the page
    loc = Utils.check_location(s, %r{http://(?:www\.)?bash\.org/\?})
    return unless loc
    # check if there are any quotes
    quotes = get_html_quotes(s[:text])
    return if quotes.empty?
    title = s[:text].ircify_html_title
    # return the first quote
    return {
          :title => title,
          :content => quotes.first.to_s,
          :bash_quotes => quotes
    }
  end

  def initialize
    super

    @bot.register_filter(:bash, :htmlinfo) { |s| bash_filter(s) }
  end

  def bash(m, params)
    id = params[:id]
    case @bot.config['bash.access'].intern
    when :xml
      xml_bash(m, id)
    else
      html_bash(m, :id => id)
    end
  end

  def search(m, params)
    esc = CGI.escape(params[:words].to_s)
    html = @bot.httputil.get("http://bash.org/?search=#{esc}")
    html_bash(m, :html => html)
  end

  def get_html_quotes(html)
    quotes = []

    html_quotes = html.split(/<p class="quote">/)
    html_quotes.each { |htqt|
      # debug htqt.inspect
      if htqt.match(/<a href="\?(\d+)"[^>]*>.*?\((-?\d+)\).*?<p class="qt">(.*)<\/p>\s+(?:<\/td>.*)?\z/m)
        num = $1
        vote = $2
        text = $3
        quotes << BashQuote.new(num, text, vote)
      end
    }
    return quotes
  end

  def html_bash(m, opts={})
    html = opts[:html]
    if not html
      id = opts[:id]
      case id
      when 'latest'
        html = @bot.httputil.get("http://bash.org/?latest")
      when nil
        html = @bot.httputil.get("http://bash.org/?random", :cache => false)
      else
        html = @bot.httputil.get("http://bash.org/?" + id)
      end
    end

    if not html
      m.reply "unable to retrieve quotes"
      return
    end

    quotes = get_html_quotes(html)

    case quotes.length
    when 0
      m.reply "no quotes found"
      return
    when 1
      quote = quotes.first
    else
      # For the time being, we only echo the first quote, but in the future we
      # may want to echo more than one for latest/random
      quote = quotes.first
    end
    m.reply quote.to_s, :split_at => /\s+\|\s+/
  end

  def xml_bash(m, id=nil)
    case id
    when 'latest'
      xml = @bot.httputil.get("http://bash.org/xml/?latest&num=1")
    when nil
      xml = @bot.httputil.get("http://bash.org/xml/?random&num=1", :cache => false)
    else
      xml = @bot.httputil.get("http://bash.org/xml/?" + id + "&num=1")
    end

    unless xml
      m.reply "bash.org rss parse failed"
      return
    end
    doc = Document.new xml
    unless doc
      m.reply "bash.org rss parse failed"
      return
    end
    doc.elements.each("*/item") {|e|
      if(id != 0)
        reply = e.elements["title"].text.gsub(/QDB: /,"") + " " + e.elements["link"].text.gsub(/QDB: /,"") + "\n"
        reply = reply + e.elements["description"].text.gsub(/\<br \/\>/, "\n")
      else
        reply = e.elements["title"].text.gsub(/QDB: /,"") + " " + e.elements["link"].text.gsub(/QDB: /,"") + "\n"
        reply = reply + e.elements["description"].text.gsub(/\<br \/\>/, "\n")
      end
      m.reply reply
    }
  end
end

plugin = BashPlugin.new

plugin.map "bash search *words", :action => :search
plugin.map "bash [:id]"

