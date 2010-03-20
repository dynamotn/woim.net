#!/usr/bin/ruby

# $Id$ 
# author   : kyanh <@viettug.org>
# purpose  : fetch list of mp3 files from http://woim.net/
# license  : GPL version 2
# home page: http://viettug.org/projects/fs/wiki/woim
# doc/usage: (described in home page)
# policy   : http://www.woim.net/forums/viewtopic.php?t=102

require 'rubygems'    # for the others
require 'curb'        # for fetching data

class Message
  def initialize(msg)
    puts ":: #{msg}"
  end
end

module Cache
  def filename(cache_id)
    "./cache/#{cache_id}"
  end

  def write(cache_id, contents)
    f = open(filename(cache_id), "w")
    f.write(contents)
    f.close
    Message.new "cache updated: #{cache_id}"
  end
  
  def read(cache_id)
    if cached?(cache_id)
      begin
        Message.new "cache loaded: #{cache_id}"
        IO.readlines(filename(cache_id)).join()
      rescue
        return nil
      end
    else
      return nil
    end
  end
  
  def cached?(cache_id)
    File.exist?(filename(cache_id))
  end
end

include Cache

class Fetch
  attr_reader :url, :cache, :cached

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
    @@agent = a if a.is_a?(String) and !a.empty?
  end
  
  def self.debug=(value)
    @@debug = value
  end

  def initialize(url, cache = nil)
    @url = url
    @cache = cache
    @cached = false
  end

  def body
    @cached = false
    if @cache
      cache = Cache::read(@cache)
      if cache
        @cached = true
        return cache
      end
    end
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
    fetch = Fetch.new(@w_url, "song_#{@w_id}")
    body = fetch.body
    if gs = body.match(%r|<param name="flashvars".*?code=(http://www\.woim\.net/.*?/#{@w_id}/.*?)">|i)
      meta_url = gs[1]
      text = fetch.cached ? body : Fetch.new(meta_url).body
      gs = text.match(%r|location="(.*?)">|i)
      link_to_mp3 = gs[1] if gs
    elsif gs = body.match(%r|<param name="FileName" value="(http://www\.woim\.net/.*?/#{@w_id}/.*?)">|i)
      meta_url = gs[1]
      text = fetch.cached ? body : Fetch.new(meta_url).body
      gs = text.match(%r|<ref href="(.*?)" />|i)
      link_to_mp3 = gs[1] if gs
    end
    if !link_to_mp3.empty? and !fetch.cached
      ct = []
      ct << "<param name=\"flashvars\" code=#{meta_url}\">"
      ct << "location=\"#{link_to_mp3}\">"
      Cache::write("song_#{@w_id}", ct.join("\n"))
    end
    return link_to_mp3
  end

  def print_mp3
    puts mp3
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

    fetch = Fetch.new("http://www.woim.net/album/#{@w_id.to_s}/index.html", "album_#{@w_id}")
    @w_text = fetch.body

    @w_title = nil
    @w_artist = nil
    @w_list = []
    
    get_info
    get_list
    write_cache unless fetch.cached
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
        puts "wget -O \"#{@w_title.sanitized}_#{s[:title].sanitized}.mp3\" \"#{s[:mp3]}\""
      end
    end
  end
  
  def print_m3u
    unless @w_list.empty?
      Message.new "-" * 46
      @w_list.each do |s|
        puts "* #{s[:title]}"
      end
      Message.new "-" * 46
      Message.new "list of mp3 files"
      Message.new "-" * 46
      @w_list.each { |s|  puts s[:mp3] }
    end
  end

private

  def write_cache
    st = []
    st << 'class="album_info">'
    st << "Album: <h1>#{@w_title}</h1>"
    st << "<tr></tr>"
    st << "<tr>Artist: href=>#{@w_artist}</a></tr>"
    @w_list.each do |song|
      st << "<td>0. href=\"http://www.woim.net/song/#{song[:id]}/\">#{song[:title]}</a>"
    end
    Cache.write("album_#{@w_id}", st.join("\n"))
    self
  end

  def get_info
    if gs = @w_text.match(%r#
                class="album_info">.*?
                  Album:  .*? <h1>(.*?)</h1>.*?
                  <tr>.*?</tr>.*?
                  <tr>.*? href=.*?>(.*?)</a>.*?</tr>
                          #mx)
      @w_title , @w_artist = gs[1,2]
      Message.new "album found #{@w_title} (performed by #{@w_artist})"
    end
    self
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
    self
  end
end

Fetch.debug = false
Fetch.proxy = nil # {:host => "localhost",:port => 3128}

albums = []
songs  = []

ARGV.each do |arg|
  if gs = arg.match(%r|album/([0-9]+)|) or gs = arg.match(%r|^([0-9]+)$|)
    albums << gs[1]
  elsif gs = arg.match(%r|song/([0-9]+)|)
    songs << gs[1]
  elsif gs = arg.match(%r|proxy=(.*?):([0-9]+)|)
    Fetch.proxy = {:host => gs[1], :port => gs[2]}
  else
    Message.new "failed to parse: #{url}"
  end
end

albums.each {|a| Album.new(a).print_m3u }
songs.each  {|s| Song.new(a).print_mp3  }
