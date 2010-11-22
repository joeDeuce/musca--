#-- vim:sw=2:et
#++
#
# :title: Script plugin for rbot
#
# Author:: Mark Kretschmann <markey@web.de>
# Copyright:: (C) 2006 Mark Kretschmann
# License:: GPL v2
#
# Create mini plugins on IRC.
#
# Scripts are little Ruby programs that run in the context of the script
# plugin. You can create them directly in an IRC channel, and invoke them just
# like normal rbot plugins.

define_structure :Command, :code, :nick, :created, :channel

class ScriptPlugin < Plugin

  def initialize
    super
    if @registry.has_key?(:commands)
      @commands = @registry[:commands]
      raise LoadError, "corrupted script database" unless @commands
    else
      @commands = Hash.new
    end
  end


  def save
    @registry[:commands] = @commands
  end


  def help( plugin, topic="" )
    case topic
    when "add"
      "Scripts are little Ruby programs that run in the context of the script plugin. You can access @bot (class Irc::Bot), m (class Irc::PrivMessage), user (class String, either the first argument, or if missing the sourcenick), and args (class Array, an array of arguments). Example: 'script add greet m.reply( 'Hello ' + user )'. Invoke the script just like a plugin: '<botnick>: greet'."
    when "allow"
      "script allow <script> for <user> [where] => allow <user> to run script <script> [where]"
    when "allow"
      "script deny <script> for <user> [where] => prevent <user> from running script <script> [where]"
    else
      "Create mini plugins on IRC. 'script add <name> <code>' => Create script named <name> with the Ruby program <code>. 'script list' => Show a list of all known scripts. 'script show <name>' => Show the source code for <name>. 'script del <name>' => Delete the script <name>. 'script eval <expr>' => evaluate expression <expr>. 'script echo <expr>' => evaluate and display expression <expr>. See also: add, allow, deny."
    end
  end

  def report_error(m, name, e)
    # ed = e.backtrace.unshift(e.inspect).join(' ')
    ed = e.inspect
    m.reply( "Script '#{name}' crapped out :( #{ed}" )
  end


  def message( m )
    name = m.message.split.first

    if m.address? and @commands.has_key?( name )
      auth_path = "script::run::#{name}".intern
      return unless @bot.auth.allow?(auth_path, m.source, m.replyto)

      code = @commands[name].code.dup.untaint

      # Convenience variables, can be accessed by scripts:
      args = m.message.split
      args.delete_at( 0 )
      user = args.empty? ? m.sourcenick : args.first

      Thread.start {
        # TODO allow different safe levels for different botusers
        $SAFE = 3

        begin
          eval( code )
        rescue Exception => e
          report_error(m, name, e)
        end
      }
      m.replied = true
    end
  end

  def handle_allow_deny(m, p)
    name = p[:stuff]
    if @commands.has_key?( name )
      @bot.plugins['auth'].auth_allow_deny(m, p.merge(
        :auth_path => "script::run::#{name}".intern
      ))
    else
      m.reply(_("%{stuff} is not a script I know of") % p)
    end
  end

  def handle_allow(m, p)
    handle_allow_deny(m, p.merge(:allow => true))
  end

  def handle_deny(m, p)
    handle_allow_deny(m, p.merge(:allow => false))
  end



  def handle_eval( m, params )
    code = params[:code].to_s.dup.untaint
    Thread.start {
      # TODO allow different safe levels for different botusers
      begin
        eval( code )
      rescue Exception => e
        report_error(m, code, e)
      end
    }
    m.replied = true
  end


  def handle_echo( m, params )
    code = params[:code].to_s.dup.untaint
    Thread.start {
      # TODO allow different safe levels for different botusers
      begin
        m.reply eval( code ).to_s
      rescue Exception => e
        report_error(m, code, e)
      end
    }
    m.replied = true
  end


  def handle_add( m, params, force = false )
    name    = params[:name]
    if !force and @commands.has_key?( name )
      m.reply( "#{m.sourcenick}: #{name} already exists. Use 'add -f' if you really want to overwrite it." )
      return
    end

    code    = params[:code].to_s
    nick    = m.sourcenick
    created = Time.new.strftime '%Y/%m/%d %H:%m'
    channel = m.target.to_s

    command = Command.new( code, nick, created, channel )
    @commands[name] = command

    m.okay
  end


  def handle_add_force( m, params )
    handle_add( m, params, true )
  end


  def handle_del( m, params )
    name = params[:name]
    unless @commands.has_key?( name )
      m.reply( "Script does not exist." ); return
    end

    @commands.delete( name )
    m.okay
  end


  def handle_list( m, params )
    if @commands.length == 0
      m.reply( "No scripts available." ); return
    end

    cmds_per_page = 30
    cmds = @commands.keys.sort
    num_pages = cmds.length / cmds_per_page + 1
    page = params[:page].to_i
    page = [page, 1].max
    page = [page, num_pages].min
    str = cmds[(page-1)*cmds_per_page, cmds_per_page].join(', ')

    m.reply "Available scripts (page #{page}/#{num_pages}): #{str}"
  end


  def handle_show( m, params )
    name = params[:name]
    unless @commands.has_key?( name )
      m.reply( "Script does not exist." ); return
    end

    cmd = @commands[name]
    m.reply( "#{cmd.code} [#{cmd.nick}, #{cmd.created} in #{cmd.channel}]" )
 end

end


plugin = ScriptPlugin.new

plugin.default_auth( 'edit', false )
plugin.default_auth( 'eval', false )
plugin.default_auth( 'echo', false )
plugin.default_auth( 'run', true )

plugin.map 'script add -f :name *code', :action => 'handle_add_force', :auth_path => 'edit'
plugin.map 'script add :name *code',    :action => 'handle_add',       :auth_path => 'edit'
plugin.map 'script del :name',          :action => 'handle_del',       :auth_path => 'edit'
plugin.map 'script eval *code',         :action => 'handle_eval'
plugin.map 'script echo *code',         :action => 'handle_echo'
plugin.map 'script list :page',         :action => 'handle_list',      :defaults => { :page => '1' }
plugin.map 'script show :name',         :action => 'handle_show'

plugin.map 'script allow :stuff for :user [*where]',
  :action => 'handle_allow',
  :requirements => {:where => /^(?:anywhere|everywhere|[io]n \S+)$/},
  :auth_path => 'edit'
plugin.map 'script deny :stuff for :user [*where]',
  :action => 'handle_deny',
  :requirements => {:where => /^(?:anywhere|everywhere|[io]n \S+)$/},
  :auth_path => 'edit'

