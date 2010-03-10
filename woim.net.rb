#!/usr/bin/ruby

require 'rubygems'
require 'curb'

class Message
  def initialize(msg)
    puts ":: #{msg}"
  end
end

class Fetch
  attr_reader :url

  @@agent = "Mozilla/5.0 (X11; U; Linux i686; en-US; Nautilus/1.0Final) Gecko/20020408"
  @@debug = false

  def self.proxy=(a)
    if a.is_a?(Hash)
      @@proxy = a
      Message.new "data fetched via proxy #{@@proxy[:host]}:#{@@proxy[:port]}"
    else
      @@proxy = nil
    end
  end
  
  def self.agent=(a)
    @@agent = a
  end
  
  def self.debug=(value)
    @@debug = value
  end

  def initialize(url)
    @url = url
  end

  def body
    begin
      Message.new "fetching #{@url}"
      c = Curl::Easy.perform(@url) do |curl|
        curl.headers["User-Agent"] = @@agent
        curl.verbose = @@debug
        if @@proxy
          curl.proxy_url  = @@proxy[:host]
          curl.proxy_port = @@proxy[:port]
        end
      end
      return c.body_str
    rescue
      return ""
    end
  end
end

class Song
  attr_reader :w_url, :w_id
  
  def initialize(song_id)
    @w_id = song_id.to_s
    @w_url = "http://www.woim.net/song/#{@w_id}/index.html"
  end

  def mp3
    link_to_mp3 = ""
    if gs = Fetch.new(@w_url).body.match(%r|<PARAM NAME="FileName" VALUE="(http://www\.woim\.net/.*?/#{@w_id}/.*?)">|i)
      meta_url = gs[1]
      text = Fetch.new(meta_url).body
      gs = text.match(%r|<REF HREF="(.*?)" />|i)
      link_to_mp3 = gs[1] if gs
    end
    return link_to_mp3
  end
end

class String
  def sanitized
    self.downcase.gsub(/[^0-9a-z_-]/,' ').gsub(' ','_')
  end
end

class Album
  attr_reader :w_id, :w_text, :w_title, :w_artist, :w_list

  def initialize(id)
    @w_id = id.to_s

    @w_text = Fetch.new("http://www.woim.net/album/#{@w_id.to_s}/index.html").body
    # @w_text = IO.readlines("./test.data.html").join()

    @w_title = nil
    @w_artist = nil
    @w_list = []
    
    get_info
    get_list
  end

  def print
    Message.new "-" * 46
    puts "Album:  #{@w_title}"
    puts "Artist: #{@w_artist}"
    unless @w_list.empty?
      Message.new "-" * 46
      @w_list.each do |s|
        puts "* #{s[:title]}"
      end
      Message.new "-" * 46
      Message.new "wget script to download mp3 file(s)"
      Message.new "-" * 46
      @w_list.each do |s|
        puts "wget -O \"#{@w_id}_#{s[:mp3].sanitized}\" \"#{s[:mp3]}\""
      end
    end
  end

private

  def get_info
    if gs = @w_text.match(%r|
                class="album_info">.*?
                  Album:  .*? <h1>(.*?)</h1>.*?
                  Artist: .*? href=.*?>(.*?)</a>
                          |mx)
      @w_title , @w_artist = gs[1,2]
      Message.new "album found #{@w_title} (performed by #{@w_artist})"
    end
  end
  
  def get_list
    w_list = []
    @w_text.scan(%r|
              <td>[0-9]+.*?
                href="http://www\.woim\.net/song/([0-9]+)/.*?>(.*?)</a>
                  |mx) \
    do |id,title|
      w_list << {:id => id, :title => title}
    end
    Message.new "#{w_list.size} song(s) found"
    w_list.each do |song|
      song[:mp3] = Song.new(song[:id]).mp3
      @w_list << {:id => song[:id], :title => song[:title], :mp3 => song[:mp3]}
    end
  end
end

Fetch.debug = false
Fetch.proxy = {:host => "localhost",:port => 3128}

Album.new(3032).print

