#-- vim:sw=2:et
#++
#
# :title: Quiz plugin for rbot
#
# Author:: Mark Kretschmann <markey@web.de>
# Author:: Jocke Andersson <ajocke@gmail.com>
# Author:: Giuseppe Bilotta <giuseppe.bilotta@gmail.com>
# Author:: Yaohan Chen <yaohan.chen@gmail.com>
#
# Copyright:: (C) 2006 Mark Kretschmann, Jocke Andersson, Giuseppe Bilotta
# Copyright:: (C) 2007 Giuseppe Bilotta, Yaohan Chen
#
# License:: GPL v2
#
# A trivia quiz game. Fast paced, featureful and fun.

# FIXME:: interesting fact: in the Quiz class, @registry.has_key? seems to be
#         case insensitive. Although this is all right for us, this leads to
#         rank vs registry mismatches. So we have to make the @rank_table
#         comparisons case insensitive as well. For the moment, redefine
#         everything to downcase before matching the nick.
#
# TODO:: define a class for the rank table. We might also need it for scoring
#        in other games.
#
# TODO:: when Ruby 2.0 gets out, fix the FIXME 2.0 UTF-8 workarounds

# Class for storing question/answer pairs
define_structure :QuizBundle, :question, :answer

# Class for storing player stats
define_structure :PlayerStats, :score, :jokers, :jokers_time
# Why do we still need jokers_time? //Firetech

# Control codes
Color = "\003"
Bold = "\002"


#######################################################################
# CLASS QuizAnswer
# Abstract an answer to a quiz question, by providing self as a string
# and a core that can be answered as an alternative. It also provides
# a boolean that tells if the core is numeric or not
#######################################################################
class QuizAnswer
  attr_writer :info

  def initialize(str)
    @string = str.strip
    @core = nil
    if @string =~ /#(.+)#/
      @core = $1
      @string.gsub!('#', '')
    end
    raise ArgumentError, "empty string can't be a valid answer!" if @string.empty?
    raise ArgumentError, "empty core can't be a valid answer!" if @core and @core.empty?

    @numeric = (core.to_i.to_s == core) || (core.to_f.to_s == core)
    @info = nil
  end

  def core
    @core || @string
  end

  def numeric?
    @numeric
  end

  def valid?(str)
    str.downcase == core.downcase || str.downcase == @string.downcase
  end

  def to_str
    [@string, @info].join
  end
  alias :to_s :to_str


end


#######################################################################
# CLASS Quiz
# One Quiz instance per channel, contains channel specific data
#######################################################################
class Quiz
  attr_accessor :registry, :registry_conf, :questions,
    :question, :answers, :canonical_answer, :answer_array,
    :first_try, :hint, :hintrange, :rank_table, :hinted, :has_errors,
    :all_seps

  def initialize( channel, registry )
    if !channel
      @registry = registry.sub_registry( 'private' )
    else
      @registry = registry.sub_registry( channel.downcase )
    end
    @has_errors = false
    @registry.each_key { |k|
      unless @registry.has_key?(k)
        @has_errors = true
        error "Data for #{k} is NOT ACCESSIBLE! Database corrupt?"
      end
    }
    if @has_errors
      debug @registry.to_a.map { |a| a.join(", ")}.join("\n")
    end

    @registry_conf = @registry.sub_registry( "config" )

    # Per-channel list of sources. If empty, the default one (quiz/quiz.rbot)
    # will be used. TODO
    @registry_conf["sources"] = [] unless @registry_conf.has_key?( "sources" )

    # Per-channel copy of the global questions table. Acts like a shuffled queue
    # from which questions are taken, until empty. Then we refill it with questions
    # from the global table.
    @registry_conf["questions"] = [] unless @registry_conf.has_key?( "questions" )

    # Autoask defaults to true
    @registry_conf["autoask"] = true unless @registry_conf.has_key?( "autoask" )

    # Autoask delay defaults to 0 (instantly)
    @registry_conf["autoask_delay"] = 0 unless @registry_conf.has_key?( "autoask_delay" )

    @questions = @registry_conf["questions"]
    @question = nil
    @answers = []
    @canonical_answer = nil
    # FIXME 2.0 UTF-8
    @answer_array = []
    @first_try = false
    # FIXME 2.0 UTF-8
    @hint = []
    @hintrange = nil
    @hinted = false

    # True if the answers is entirely done by separators
    @all_seps = false

    # We keep this array of player stats for performance reasons. It's sorted by score
    # and always synced with the registry player stats hash. This way we can do fast
    # rank lookups, without extra sorting.
    @rank_table = @registry.to_a.sort { |a,b| b[1].score<=>a[1].score }
  end
end


#######################################################################
# CLASS QuizPlugin
#######################################################################
class QuizPlugin < Plugin
  Config.register Config::BooleanValue.new('quiz.dotted_nicks',
    :default => true,
    :desc => "When true, nicks in the top X scores will be camouflaged to prevent IRC hilighting")

  Config.register Config::ArrayValue.new('quiz.sources',
    :default => ['quiz.rbot'],
    :desc => "List of files and URLs that will be used to retrieve quiz questions")


  Config.register Config::IntegerValue.new('quiz.max_jokers',
    :default => 3,
    :desc => "Maximum number of jokers a player can gain")

  def initialize()
    super

    @questions = Array.new
    @quizzes = Hash.new
    @waiting = Hash.new
    @ask_mutex = Mutex.new
  end

  # Function that returns whether a char is a "separator", used for hints
  #
  def is_sep( ch )
    return ch !~ /^\w$/u
  end


  # Fetches questions from the data sources, which can be either local files
  # (in quiz/) or web pages.
  #
  def fetch_data( m )
    # Read the winning messages file
    @win_messages = Array.new
    winfile = datafile 'win_messages'
    if File.exists? winfile
      IO.foreach(winfile) { |line| @win_messages << line.chomp }
    else
      warning( "win_messages file not found!" )
      # Fill the array with a least one message or code accessing it would fail
      @win_messages << "<who> guessed right! The answer was <answer>"
    end

    m.reply "Fetching questions ..."

    # TODO Per-channel sources

    data = ""
    @bot.config['quiz.sources'].each { |p|
      if p =~ /^https?:\/\//
        # Wiki data
        begin
          serverdata = @bot.httputil.get(p) # "http://amarok.kde.org/amarokwiki/index.php/Rbot_Quiz"
          serverdata = serverdata.split( "QUIZ DATA START\n" )[1]
          serverdata = serverdata.split( "\nQUIZ DATA END" )[0]
          serverdata = serverdata.gsub( /&nbsp;/, " " ).gsub( /&amp;/, "&" ).gsub( /&quot;/, "\"" )
          data << "\n\n" << serverdata
        rescue
          m.reply "Failed to download questions from #{p}, ignoring sources"
        end
      else
        path = datafile p
        debug "Fetching from #{path}"

        # Local data
        begin
          data << "\n\n" << File.read(path)
        rescue
          m.reply "Failed to read from local database file #{p}, skipping."
        end
      end
    }

    @questions.clear

    # Fuse together and remove comments, then split
    entries = data.strip.gsub( /^#.*$/, "" ).split( /(?:^|\n+)Question: / )

    entries.each do |e|
      p = e.split( "\n" )
      # We'll need at least two lines of data
      unless p.size < 2
        # Check if question isn't empty
        if p[0].length > 0
          while p[1].match( /^Answer: (.*)$/ ) == nil and p.size > 2
            # Delete all lines between the question and the answer
            p.delete_at(1)
          end
          p[1] = p[1].gsub( /Answer: /, "" ).strip
          # If the answer was found
          if p[1].length > 0
            # Add the data to the array
            b = QuizBundle.new( p[0], p[1] )
            @questions << b
          end
        end
      end
    end

    m.reply "done, #{@questions.length} questions loaded."
  end


  # Returns new Quiz instance for channel, or existing one
  #
  def create_quiz( channel )
    unless @quizzes.has_key?( channel )
      @quizzes[channel] = Quiz.new( channel, @registry )
    end

    if @quizzes[channel].has_errors
      return nil
    else
      return @quizzes[channel]
    end
  end


  def say_score( m, nick )
    chan = m.channel
    q = create_quiz( chan )
    if q.nil?
      m.reply "Sorry, the quiz database for #{chan} seems to be corrupt"
      return
    end

    if q.registry.has_key?( nick )
      score = q.registry[nick].score
      jokers = q.registry[nick].jokers

      rank = 0
      q.rank_table.each_index { |rank| break if nick.downcase == q.rank_table[rank][0].downcase }
      rank += 1

      m.reply "#{nick}'s score is: #{score}    Rank: #{rank}    Jokers: #{jokers}"
    else
      m.reply "#{nick} does not have a score yet. Lamer."
    end
  end


  def help( plugin, topic="" )
    if topic == "admin"
      "Quiz game aministration commands (requires authentication): 'quiz autoask <on/off>' => enable/disable autoask mode. 'quiz autoask delay <secs>' => delay next quiz by <secs> seconds when in autoask mode. 'quiz transfer <source> <dest> [score] [jokers]' => transfer [score] points and [jokers] jokers from <source> to <dest> (default is entire score and all jokers). 'quiz setscore <player> <score>' => set <player>'s score to <score>. 'quiz setjokers <player> <jokers>' => set <player>'s number of jokers to <jokers>. 'quiz deleteplayer <player>' => delete one player from the rank table (only works when score and jokers are set to 0). 'quiz cleanup' => remove players with no points and no jokers."
    else
      urls = @bot.config['quiz.sources'].select { |p| p =~ /^https?:\/\// }
      "A multiplayer trivia quiz. 'quiz' => ask a question. 'quiz hint' => get a hint. 'quiz solve' => solve this question. 'quiz skip' => skip to next question. 'quiz joker' => draw a joker to win this round. 'quiz score [player]' => show score for [player] (default is yourself). 'quiz top5' => show top 5 players. 'quiz top <number>' => show top <number> players (max 50). 'quiz stats' => show some statistics. 'quiz fetch' => refetch questions from databases. 'quiz refresh' => refresh the question pool for this channel." + (urls.empty? ? "" : "\nYou can add new questions at #{urls.join(', ')}")
    end
  end


  # Updates the per-channel rank table, which is kept for performance reasons.
  # This table contains all players sorted by rank.
  #
  def calculate_ranks( m, q, nick )
    if q.registry.has_key?( nick )
      stats = q.registry[nick]

      # Find player in table
      found_player = false
      i = 0
      q.rank_table.each_index do |i|
        if nick.downcase == q.rank_table[i][0].downcase
          found_player = true
          break
        end
      end

      # Remove player from old position
      if found_player
        old_rank = i
        q.rank_table.delete_at( i )
      else
        old_rank = nil
      end

      # Insert player at new position
      inserted = false
      q.rank_table.each_index do |i|
        if stats.score > q.rank_table[i][1].score
          q.rank_table[i,0] = [[nick, stats]]
          inserted = true
          break
        end
      end

      # If less than all other players' scores, append to table
      unless inserted
        i += 1 unless q.rank_table.empty?
        q.rank_table << [nick, stats]
      end

      # Print congratulations/condolences if the player's rank has changed
      unless old_rank.nil?
        if i < old_rank
          m.reply "#{nick} ascends to rank #{i + 1}. Congratulations :)"
        elsif i > old_rank
          m.reply "#{nick} slides down to rank #{i + 1}. So Sorry! NOT. :p"
        end
      end
    else
      q.rank_table << [[nick, PlayerStats.new( 1 )]]
    end
  end


  # Reimplemented from Plugin
  #
  def message(m)
    chan = m.channel
    return unless @quizzes.has_key?( chan )
    q = @quizzes[chan]

    return if q.question == nil

    message = m.message.downcase.strip

    nick = m.sourcenick.to_s

    # Support multiple alternate answers and cores
    answer = q.answers.find { |ans| ans.valid?(message) }
    if answer
      # List canonical answer which the hint was based on, to avoid confusion
      # FIXME display this more friendly
      answer.info = " (hints were for alternate answer #{q.canonical_answer.core})" if answer != q.canonical_answer and q.hinted

      points = 1
      if q.first_try
        points += 1
        reply = "WHOPEEE! #{nick} got it on the first try! That's worth an extra point. Answer was: #{answer}"
      elsif q.rank_table.length >= 1 and nick.downcase == q.rank_table[0][0].downcase
        reply = "THE QUIZ CHAMPION defends his throne! Seems like #{nick} is invicible! Answer was: #{answer}"
      elsif q.rank_table.length >= 2 and nick.downcase == q.rank_table[1][0].downcase
        reply = "THE SECOND CHAMPION is on the way up! Hurry up #{nick}, you only need #{q.rank_table[0][1].score - q.rank_table[1][1].score - 1} points to beat the king! Answer was: #{answer}"
      elsif    q.rank_table.length >= 3 and nick.downcase == q.rank_table[2][0].downcase
        reply = "THE THIRD CHAMPION strikes again! Give it all #{nick}, with #{q.rank_table[1][1].score - q.rank_table[2][1].score - 1} more points you'll reach the 2nd place! Answer was: #{answer}"
      else
        reply = @win_messages[rand( @win_messages.length )].dup
        reply.gsub!( "<who>", nick )
        reply.gsub!( "<answer>", answer )
      end

      m.reply reply

      player = nil
      if q.registry.has_key?(nick)
        player = q.registry[nick]
      else
        player = PlayerStats.new( 0, 0, 0 )
      end

      player.score = player.score + points

      # Reward player with a joker every X points
      if player.score % 15 == 0 and player.jokers < @bot.config['quiz.max_jokers']
        player.jokers += 1
        m.reply "#{nick} gains a new joker. Rejoice :)"
      end

      q.registry[nick] = player
      calculate_ranks( m, q, nick)

      q.question = nil
      if q.registry_conf["autoask"]
        delay = q.registry_conf["autoask_delay"]
        if delay > 0
          m.reply "#{Bold}#{Color}03Next question in #{Bold}#{delay}#{Bold} seconds"
          timer = @bot.timer.add_once(delay) {
            @ask_mutex.synchronize do
              @waiting.delete(chan)
            end
            cmd_quiz( m, nil)
          }
          @waiting[chan] = timer
        else
          cmd_quiz( m, nil )
        end
      end
    else
      # First try is used, and it wasn't the answer.
      q.first_try = false
    end
  end


  # Stretches an IRC nick with dots, simply to make the client not trigger a hilight,
  # which is annoying for those not watching. Example: markey -> m.a.r.k.e.y
  #
  def unhilight_nick( nick )
    return nick unless @bot.config['quiz.dotted_nicks']
    return nick.split(//).join(".")
  end


  #######################################################################
  # Command handling
  #######################################################################
  def cmd_quiz( m, params )
    fetch_data( m ) if @questions.empty?
    chan = m.channel

    @ask_mutex.synchronize do
      if @waiting.has_key?(chan)
        m.reply "Next quiz question will be automatically asked soon, have patience"
        return
      end
    end

    q = create_quiz( chan )
    if q.nil?
      m.reply "Sorry, the quiz database for #{chan} seems to be corrupt"
      return
    end

    if q.question
      m.reply "#{Bold}#{Color}03Current question: #{Color}#{Bold}#{q.question}"
      m.reply "Hint: #{q.hint}" if q.hinted
      return
    end

    # Fill per-channel questions buffer
    if q.questions.empty?
      q.questions = @questions.sort_by { rand }
    end

    # pick a question and delete it (delete_at returns the deleted item)
    picked = q.questions.delete_at( rand(q.questions.length) )

    q.question = picked.question
    q.answers = picked.answer.split(/\s+\|\|\s+/).map { |ans| QuizAnswer.new(ans) }

    # Check if any core answer is numerical and tell the players so, if that's the case
    # The rather obscure statement is needed because to_i and to_f returns 99(.0) for "99 red balloons", and 0 for "balloon"
    #
    # The "canonical answer" is also determined here, defined to be the first found numerical answer, or
    # the first core.
    numeric = q.answers.find { |ans| ans.numeric? }
    if numeric
        q.question += "#{Color}07 (Numerical answer)#{Color}"
        q.canonical_answer = numeric
    else
        q.canonical_answer = q.answers.first
    end

    q.first_try = true

    # FIXME 2.0 UTF-8
    q.hint = []
    q.answer_array.clear
    q.canonical_answer.core.scan(/./u) { |ch|
      if is_sep(ch)
        q.hint << ch
      else
        q.hint << "^"
      end
      q.answer_array << ch
    }
    q.all_seps = false
    # It's possible that an answer is entirely done by separators,
    # in which case we'll hide everything
    if q.answer_array == q.hint
      q.hint.map! { |ch|
        "^"
      }
      q.all_seps = true
    end
    q.hinted = false

    # Generate array of unique random range
    q.hintrange = (0..q.hint.length-1).sort_by{ rand }

    m.reply "#{Bold}#{Color}03Question: #{Color}#{Bold}" + q.question
  end


  def cmd_solve( m, params )
    chan = m.channel

    return unless @quizzes.has_key?( chan )
    q = @quizzes[chan]

    m.reply "The correct answer was: #{q.canonical_answer}"

    q.question = nil

    cmd_quiz( m, nil ) if q.registry_conf["autoask"]
  end


  def cmd_hint( m, params )
    chan = m.channel
    nick = m.sourcenick.to_s

    return unless @quizzes.has_key?(chan)
    q = @quizzes[chan]

    if q.question == nil
      m.reply "#{nick}: Get a question first!"
    else
      num_chars = case q.hintrange.length    # Number of characters to reveal
      when 25..1000 then 7
      when 20..1000 then 6
      when 16..1000 then 5
      when 12..1000 then 4
      when  8..1000 then 3
      when  5..1000 then 2
      when  1..1000 then 1
      end

      # FIXME 2.0 UTF-8
      num_chars.times do
        begin
          index = q.hintrange.pop
          # New hint char until the char isn't a "separator" (space etc.)
        end while is_sep(q.answer_array[index]) and not q.all_seps
        q.hint[index] = q.answer_array[index]
      end
      m.reply "Hint: #{q.hint}"
      q.hinted = true

      # FIXME 2.0 UTF-8
      if q.hint == q.answer_array
        m.reply "#{Bold}#{Color}04BUST!#{Color}#{Bold} This round is over. #{Color}04Minus one point for #{nick}#{Color}."

        stats = nil
        if q.registry.has_key?( nick )
          stats = q.registry[nick]
        else
          stats = PlayerStats.new( 0, 0, 0 )
        end

        stats["score"] = stats.score - 1
        q.registry[nick] = stats

        calculate_ranks( m, q, nick)

        q.question = nil
        cmd_quiz( m, nil ) if q.registry_conf["autoask"]
      end
    end
  end


  def cmd_skip( m, params )
    chan = m.channel
    return unless @quizzes.has_key?(chan)
    q = @quizzes[chan]

    q.question = nil
    cmd_quiz( m, params )
  end


  def cmd_joker( m, params )
    chan = m.channel
    nick = m.sourcenick.to_s
    q = create_quiz(chan)
    if q.nil?
      m.reply "Sorry, the quiz database for #{chan} seems to be corrupt"
      return
    end

    if q.question == nil
      m.reply "#{nick}: There is no open question."
      return
    end

    if q.registry[nick].jokers > 0
      player = q.registry[nick]
      player.jokers -= 1
      player.score += 1
      q.registry[nick] = player

      calculate_ranks( m, q, nick )

      if player.jokers != 1
        jokers = "jokers"
      else
        jokers = "joker"
      end
      m.reply "#{Bold}#{Color}12JOKER!#{Color}#{Bold} #{nick} draws a joker and wins this round. You have #{player.jokers} #{jokers} left."
      m.reply "The answer was: #{q.canonical_answer}."

      q.question = nil
      cmd_quiz( m, nil ) if q.registry_conf["autoask"]
    else
      m.reply "#{nick}: You don't have any jokers left ;("
    end
  end


  def cmd_fetch( m, params )
    fetch_data( m )
  end


  def cmd_refresh( m, params )
    q = create_quiz(m.channel)
    q.questions.clear
    fetch_data(m)
    cmd_quiz( m, params )
  end


  def cmd_top5( m, params )
    chan = m.channel
    q = create_quiz( chan )
    if q.nil?
      m.reply "Sorry, the quiz database for #{chan} seems to be corrupt"
      return
    end

    if q.rank_table.empty?
      m.reply "There are no scores known yet!"
      return
    end

    m.reply "* Top 5 Players for #{chan}:"

    [5, q.rank_table.length].min.times do |i|
      player = q.rank_table[i]
      nick = player[0]
      score = player[1].score
      m.reply "    #{i + 1}. #{unhilight_nick( nick )} (#{score})"
    end
  end


  def cmd_top_number( m, params )
    num = params[:number].to_i
    return if num < 1 or num > 50
    chan = m.channel
    q = create_quiz( chan )
    if q.nil?
      m.reply "Sorry, the quiz database for #{chan} seems to be corrupt"
      return
    end

    if q.rank_table.empty?
      m.reply "There are no scores known yet!"
      return
    end

    ar = []
    m.reply "* Top #{num} Players for #{chan}:"
    n = [ num, q.rank_table.length ].min
    n.times do |i|
      player = q.rank_table[i]
      nick = player[0]
      score = player[1].score
      ar << "#{i + 1}. #{unhilight_nick( nick )} (#{score})"
    end
    m.reply ar.join(" | "), :split_at => /\s+\|\s+/
  end


  def cmd_stats( m, params )
    fetch_data( m ) if @questions.empty?

    m.reply "* Total Number of Questions:"
    m.reply "    #{@questions.length}"
  end


  def cmd_score( m, params )
    nick = m.sourcenick.to_s
    say_score( m, nick )
  end


  def cmd_score_player( m, params )
    say_score( m, params[:player] )
  end


  def cmd_autoask( m, params )
    chan = m.channel
    q = create_quiz( chan )
    if q.nil?
      m.reply "Sorry, the quiz database for #{chan} seems to be corrupt"
      return
    end

    case params[:enable].downcase
    when "on", "true"
      q.registry_conf["autoask"] = true
      m.reply "Enabled autoask mode."
      cmd_quiz( m, nil ) if q.question == nil
    when "off", "false"
      q.registry_conf["autoask"] = false
      m.reply "Disabled autoask mode."
    else
      m.reply "Invalid autoask parameter. Use 'on' or 'off'."
    end
  end

  def cmd_autoask_delay( m, params )
    chan = m.channel
    q = create_quiz( chan )
    if q.nil?
      m.reply "Sorry, the quiz database for #{chan} seems to be corrupt"
      return
    end

    delay = params[:time].to_i
    q.registry_conf["autoask_delay"] = delay
    m.reply "Autoask delay now #{q.registry_conf['autoask_delay']} seconds"
  end


  def cmd_transfer( m, params )
    chan = m.channel
    q = create_quiz( chan )
    if q.nil?
      m.reply "Sorry, the quiz database for #{chan} seems to be corrupt"
      return
    end

    debug q.rank_table.inspect

    source = params[:source]
    dest = params[:dest]
    transscore = params[:score].to_i
    transjokers = params[:jokers].to_i
    debug "Transferring #{transscore} points and #{transjokers} jokers from #{source} to #{dest}"

    if q.registry.has_key?(source)
      sourceplayer = q.registry[source]
      score = sourceplayer.score
      if transscore == -1
        transscore = score
      end
      if score < transscore
        m.reply "#{source} only has #{score} points!"
        return
      end
      jokers = sourceplayer.jokers
      if transjokers == -1
        transjokers = jokers
      end
      if jokers < transjokers
        m.reply "#{source} only has #{jokers} jokers!!"
        return
      end
      if q.registry.has_key?(dest)
        destplayer = q.registry[dest]
      else
        destplayer = PlayerStats.new(0,0,0)
      end

      if sourceplayer.object_id == destplayer.object_id
        m.reply "Source and destination are the same, I'm not going to touch them"
        return
      end

      sourceplayer.score -= transscore
      destplayer.score += transscore
      sourceplayer.jokers -= transjokers
      destplayer.jokers += transjokers

      q.registry[source] = sourceplayer
      calculate_ranks(m, q, source)

      q.registry[dest] = destplayer
      calculate_ranks(m, q, dest)

      m.reply "Transferred #{transscore} points and #{transjokers} jokers from #{source} to #{dest}"
    else
      m.reply "#{source} doesn't have any points!"
    end
  end


  def cmd_del_player( m, params )
    chan = m.channel
    q = create_quiz( chan )
    if q.nil?
      m.reply "Sorry, the quiz database for #{chan} seems to be corrupt"
      return
    end

    debug q.rank_table.inspect

    nick = params[:nick]
    if q.registry.has_key?(nick)
      player = q.registry[nick]
      score = player.score
      if score != 0
        m.reply "Can't delete player #{nick} with score #{score}."
        return
      end
      jokers = player.jokers
      if jokers != 0
        m.reply "Can't delete player #{nick} with #{jokers} jokers."
        return
      end
      q.registry.delete(nick)

      player_rank = nil
      q.rank_table.each_index { |rank|
        if nick.downcase == q.rank_table[rank][0].downcase
          player_rank = rank
          break
        end
      }
      q.rank_table.delete_at(player_rank)

      m.reply "Player #{nick} deleted."
    else
      m.reply "Player #{nick} isn't even in the database."
    end
  end


  def cmd_set_score(m, params)
    chan = m.channel
    q = create_quiz( chan )
    if q.nil?
      m.reply "Sorry, the quiz database for #{chan} seems to be corrupt"
      return
    end
    debug q.rank_table.inspect

    nick = params[:nick]
    val = params[:score].to_i
    if q.registry.has_key?(nick)
      player = q.registry[nick]
      player.score = val
    else
      player = PlayerStats.new( val, 0, 0)
    end
    q.registry[nick] = player
    calculate_ranks(m, q, nick)
    m.reply "Score for player #{nick} set to #{val}."
  end


  def cmd_set_jokers(m, params)
    chan = m.channel
    q = create_quiz( chan )
    if q.nil?
      m.reply "Sorry, the quiz database for #{chan} seems to be corrupt"
      return
    end
    debug q.rank_table.inspect

    nick = params[:nick]
    val = [params[:jokers].to_i, @bot.config['quiz.max_jokers']].min
    if q.registry.has_key?(nick)
      player = q.registry[nick]
      player.jokers = val
    else
      player = PlayerStats.new( 0, val, 0)
    end
    q.registry[nick] = player
    m.reply "Jokers for player #{nick} set to #{val}."
  end


  def cmd_cleanup(m, params)
    chan = m.channel
    q = create_quiz( chan )
    if q.nil?
      m.reply "Sorry, the quiz database for #{chan} seems to be corrupt"
      return
    end

    null_players = []
    q.registry.each { |nick, player|
      null_players << nick if player.jokers == 0 and player.score == 0
    }
    debug "Cleaning up by removing #{null_players * ', '}"
    null_players.each { |nick|
      cmd_del_player(m, :nick => nick)
    }

  end

  def stop(m, params)
    unless m.public?
      m.reply 'you must be on some channel to use this command'
      return
    end
    if @quizzes.delete m.channel
      @ask_mutex.synchronize do
        t = @waiting.delete(m.channel)
        @bot.timer.remove t if t
      end
      m.okay
    else
      m.reply(_("there is no active quiz on #{m.channel}"))
    end
  end

end

plugin = QuizPlugin.new
plugin.default_auth( 'edit', false )

# Normal commands
plugin.map 'quiz',                  :action => 'cmd_quiz'
plugin.map 'quiz solve',            :action => 'cmd_solve'
plugin.map 'quiz hint',             :action => 'cmd_hint'
plugin.map 'quiz skip',             :action => 'cmd_skip'
plugin.map 'quiz joker',            :action => 'cmd_joker'
plugin.map 'quiz score',            :action => 'cmd_score'
plugin.map 'quiz score :player',    :action => 'cmd_score_player'
plugin.map 'quiz fetch',            :action => 'cmd_fetch'
plugin.map 'quiz refresh',          :action => 'cmd_refresh'
plugin.map 'quiz top5',             :action => 'cmd_top5'
plugin.map 'quiz top :number',      :action => 'cmd_top_number'
plugin.map 'quiz stats',            :action => 'cmd_stats'
plugin.map 'quiz stop', :action => :stop

# Admin commands
plugin.map 'quiz autoask :enable',  :action => 'cmd_autoask', :auth_path => 'edit'
plugin.map 'quiz autoask delay :time',  :action => 'cmd_autoask_delay', :auth_path => 'edit', :requirements => {:time => /\d+/}
plugin.map 'quiz transfer :source :dest :score :jokers', :action => 'cmd_transfer', :auth_path => 'edit', :defaults => {:score => '-1', :jokers => '-1'}
plugin.map 'quiz deleteplayer :nick', :action => 'cmd_del_player', :auth_path => 'edit'
plugin.map 'quiz setscore :nick :score', :action => 'cmd_set_score', :auth_path => 'edit'
plugin.map 'quiz setjokers :nick :jokers', :action => 'cmd_set_jokers', :auth_path => 'edit'
plugin.map 'quiz cleanup', :action => 'cmd_cleanup', :auth_path => 'edit'
