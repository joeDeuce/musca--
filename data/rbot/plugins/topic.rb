#-- vim:sw=2:et
#++
#
# :title: Topic manipulation plugin for rbot
#
# Author:: Giuseppe Bilotta <giuseppe.bilotta@gmail.com>
# Copyright:: (C) 2006-2007 Giuseppe Bilotta
# License:: GPL v2
#
# Add a bunch of topic manipulation features

class TopicPlugin < Plugin
  def initialize
    super
    @separator = "|" # default separator
  end

  def help(plugin, topic="")
    case plugin
    when "topic"
      case topic
      when "add"
        return "topic add <text> => add <text> at the end the topic"
      when "prepend"
        return "topic prepend <text> => add <text> at the beginning of the topic"
      when "addat"
        return "topic addat <num> <text> => add <text> at position <num> of the topic"
      when "del", "delete"
        return "topic del <num> => remove section <num> from the topic"
      when "replace"
        return "topic replace <num> <text> => Replaces section <num> with <text>"
      when "sep", "separator"
        return "topic sep(arator) [<text>] => get or set the topic section separator"
      when "learn"
        return "topic learn => remembers the topic for later"
      when "restore"
        return "topic restore => resets the topic to the latest remembered one"
      when "clear"
        return "topic clear => clears the topic"
      when "set"
        return "topic set <text> => sets the topic to <text>"
      when "undo"
        return "topic undo => undoes the latest change to the topic"
      else
        return "topic add(at)|prepend|del(ete)|replace|sep(arator)|learn|restore|clear|set|undo: " + \
               "manipulate the topic of the current channel; use topic <#channel> <command> " + \
               "for private addressing"
      end
    end
  end

  def handletopic(m, param)
    return unless m.kind_of?(PrivMessage)
    if m.public?
      ch = m.channel
    else
      ch = m.server.get_channel(param[:channel])
      unless ch
        m.reply("I am not in channel #{param[:channel]}")
        return
      end
    end
    cmd = param[:command]
    txt = param[:text].to_s

    case cmd
    when /^a(dd|ppend)$/
      topicappend(m, ch, txt)
    when 'prepend'
      topicprepend(m, ch, txt)
    when 'addat'
      if txt =~ /\s*(-?\d+)\s+(.*)\s*/
        num = $1.to_i - 1
        num += 1 if num < 0
        txt = $2
        topicaddat(m, ch, num, txt)
      end
    when /^del(ete)?$/
      if txt =~ /\s*(-?\d+)\s*/
        num=$1.to_i - 1
        num += 1 if num < 0
        topicdel(m, ch, num)
      end
    when 'set'
      topicset(m, ch, txt)
    when 'clear'
      topicset(m, ch, '')
    when /^sep(arator)?$/
      topicsep(m, ch, txt)
    when 'learn'
      learntopic(m, ch)
    when 'replace'
      if txt =~ /\s*(-?\d+)\s+(.*)\s*/
        num = $1.to_i - 1
        num += 1 if num < 0
        txt = $2
        replacetopic(m, ch, num, txt)
      end
    when 'restore'
      restoretopic(m, ch)
    when 'undo'
      undotopic(m, ch)
    else
      m.reply 'unknown command'
    end
  end

  def topicsep(m, ch, txt)
    return if !@bot.auth.allow?("topic::edit::separator", m.source, m.replyto)
    if txt
      sep = txt.strip
      if sep != ""
        setsep(ch, sep)
      end
    end
    m.reply "Topic separator set to #{getsep(ch)}"
  end

  def setsep(ch, sep)
    raise unless ch.class <= Irc::Channel
    # TODO multiserver
    k = ch.downcase

    if @registry.has_key?(k)
      data = @registry[k]
    else
      data = Hash.new
    end

    oldsep = getsep(ch)
    topic = ch.topic.text
    topicarray = topic.split(/\s+#{Regexp.escape(oldsep)}\s*/)

    if sep != oldsep and topicarray.length > 0
      newtopic = topicarray.join(" #{sep} ")
      @bot.topic ch, newtopic if newtopic != topic
    end

    data[:separator] = sep
    @registry[k] = data
  end

  def getsep(ch)
    raise unless ch.class <= Irc::Channel
    # TODO multiserver
    k = ch.downcase

    if @registry.has_key?(k)
      if @registry[k].has_key?(:separator)
        return @registry[k][:separator]
      end
    end
    return @separator
  end

  def topicaddat(m, ch, num, txt)
    return if !@bot.auth.allow?("topic::edit::add", m.source, m.replyto)
    sep = getsep(ch)
    topic = ch.topic.text
    topicarray = topic.split(/\s+#{Regexp.escape(sep)}\s*/)
    topicarray.insert(num, txt)
    newtopic = topicarray.join(" #{sep} ")
    changetopic(m, ch, newtopic)
  end

  def topicappend(m, ch, txt)
    topicaddat(m, ch, -1, txt)
  end

  def topicprepend(m, ch, txt)
    topicaddat(m, ch, 0, txt)
  end

  def topicdel(m, ch, num)
    return if !@bot.auth.allow?("topic::edit::del", m.source, m.replyto)
    sep = getsep(ch)
    topic = ch.topic.text
    topicarray = topic.split(/\s+#{Regexp.escape(sep)}\s*/)
    topicarray.delete_at(num)
    newtopic = topicarray.join(" #{sep} ")
    changetopic(m, ch, newtopic)
  end

  def learntopic(m, ch)
    return if !@bot.auth.allow?("topic::store::store", m.source, m.replyto)
    topic = ch.topic.text
    k = ch.downcase
    if @registry.has_key?(k)
      data = @registry[k]
    else
      data = Hash.new
    end
    data[:topic] = topic
    @registry[k] = data
    m.okay
  end

  def replacetopic(m, ch, num, txt)
    return if !@bot.auth.allow?("topic::edit::replace", m.source, m.replyto)
    sep = getsep(ch)
    topic = ch.topic.text
    topicarray = topic.split(/\s+#{Regexp.escape(sep)}\s*/)
    topicarray[num] = txt
    newtopic = topicarray.join(" #{sep} ")
    changetopic(m, ch, newtopic)
  end

  def restoretopic(m, ch)
    return if !@bot.auth.allow?("topic::store::restore", m.source, m.replyto)
    k = ch.downcase
    if @registry.has_key?(k) && @registry[k].has_key?(:topic)
      topic = @registry[k][:topic]
      topicset(m, ch, topic)
    else
      m.reply "I don't remember any topic for #{ch}"
    end
  end

  def topicset(m, ch, text)
    return if !@bot.auth.allow?("topic::edit::replace", m.source, m.replyto)
    changetopic(m, ch, text)
  end

  # This method changes the topic on channel +ch+ to +text+, storing
  # the previous topic for undo
  def changetopic(m, ch, text)
    k = ch.downcase
    if @registry.has_key?(k)
      data = @registry[k]
    else
      data = Hash.new
    end

    data[:oldtopic] = ch.topic.text
    @registry[k] = data

    @bot.topic ch, text
  end

  def undotopic(m, ch)
    k = ch.downcase
    if @registry.has_key?(k)
      data = @registry[k]
      if data.has_key?(:oldtopic)
        changetopic(m, ch, data[:oldtopic].dup)
        return
      end
    end

    m.reply "No recent changes were recorded for #{ch}"
  end

end
plugin = TopicPlugin.new

plugin.map 'topic :command [*text]', :action => 'handletopic', :public => true, :private => false
plugin.map 'topic :channel :command [*text]', :action => 'handletopic', :public => false, :private => true

plugin.default_auth('*', false)


