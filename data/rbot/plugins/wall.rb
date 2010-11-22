#-- vim:sw=2:et
#++
#
# :title: Wall plugin
#
# Author:: Giuseppe Bilotta <giuseppe.bilotta@gmail.com>
# Copyright:: (C) 2008 Giuseppe Bilotta
# License:: GPLv2
#
# Wall plugin: !wall to show the writing on the wall, !wall whatever to write
# whatever on the wall
#
# The wall is global for all rbots and is available at http://ruby-rbot.org/wall/

class WallPlugin < Plugin

  Config.register Config::ArrayValue.new('wall.readers',
     :default => ['toilet', 'figlet'],
     :desc => _('figlet method to use to display the writing on the wall (nil for none)'),
     :validate => Proc.new { |v| v !~ /\s|`/ },
     :on_change => Proc.new { |bot, v| bot.plugins['figlet'].test_toilet })

  def help(plugin, topic="")
    "wall => read latest writing on the wall: http://ruby-rbot.org/wall"
  end

  def write_wall(m, p)
    m.reply _("writing on the wall not implemented yet")
  end

  def read_wall(m, p)
    wall = @bot.httputil.get('http://ruby-rbot.org/wall/', :cache => false)
    if wall.nil_or_empty?
      m.reply _("No writing on the wall")
      return
    end
    if @bot.plugins['figlet']
      reader = nil
      @bot.config['wall.readers'].each { |p|
        plug = p.intern rescue nil
        if @bot.plugins['figlet'].has[plug]
          reader = plug
          break
        end
      }
      if reader
        @bot.plugins['figlet'].figlet m, :plugin => reader,
          :message => wall
        return
      end
    end
    m.reply(_("The writing on the wall reads: %{wall}") % {
      :wall => wall
    })
  end
end

wall = WallPlugin.new
wall.map 'wall', :action => :read_wall
wall.map 'wall *text', :action => :write_wall
