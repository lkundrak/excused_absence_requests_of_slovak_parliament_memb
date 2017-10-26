require 'pp'
require 'nokogiri'
require 'mechanize'
require 'watir'
require 'digest'
require 'scraperwiki'

BASE_URL = 'http://www.nrsr.sk/web/Default.aspx?sid=poslanci/ospravedlnenia_result'.freeze
URL_SUF = '&DatumOd=1900-1-1%200:0:0&DatumDo=2100-1-1%200:0:0&CisSchodze='.freeze
PL = 'http://www.nrsr.sk/web/Default.aspx?sid=poslanci/zoznam_abc&ListType=0&CisObdobia='.freeze

@agent = Mechanize.new

def list_mops
  page = @agent.get('http://www.nrsr.sk/web/Default.aspx?sid=poslanci/zoznam_abc&ListType=0&CisObdobia=1')
  termx = page.xpath('//select[@id = "_sectionLayoutContainer_ctl01__currentTerm"]//@value').map(&:value).max.to_i
  (2..termx).each do |term|
    pp "in term #{term}"
    page = @agent.get("#{PL}#{term}")
    page.xpath('//div[@class = "mps_list"]//li//a').each do |member|
      l = member.attr('href')
      i = l.match('.*PoslanecID=(.*)&.*')
      yield mop_id: i[1], name: member.text, term: term, url: "http://www.nrsr.sk/#{l}"
      # p id: i[1], name: member.text, term: term, url: "http://www.nrsr.sk/#{l}"
    end
  end
end

def pager(url)
  pages = []
  page = @agent.get(url)
  pages.push(page) if page.at('table.tab_zoznam')
  if page.at('//table[@class="tab_zoznam"]//table')
    links = page.xpath('//table[@class="tab_zoznam"]//table//tr/td//@href').map(&:value).uniq
    links.each do |link|
      link.slice! 'javascript:'
      begin
        br = Watir::Browser.start(url, :phantomjs)
      rescue Net::ReadTimeout, Net::HTTPRequestTimeOut, Errno::ETIMEDOUT, Errno::ECONNREFUSED => ex
        puts "#{ex.class} detected, retrying"
        retry
      end
      br.execute_script(link)
      sleep 5
      pages.push(Nokogiri::HTML(br.html))
    end
  end
  pages
end

def excuses
  list_mops do |excuse|
    excuse_url = "#{BASE_URL}&PoslanecMasterID=#{excuse[:mop_id]}&CisObdobia=#{excuse[:term]}#{URL_SUF}"
    pages = pager(excuse_url)
    pages.each do |page|
      page.at('table.tab_zoznam').search('tr').each do |r|
        next if r.attr('class') == 'tab_zoznam_header'
        next if r.attr('class') == 'pager'
        next if r.search('td')[0].text.strip.length <= 2
        yield name: excuse[:name],
              mop_id: excuse[:mop_id],
              date: r.search('td')[2].text.strip,
              term: excuse[:term],
              party: r.search('td')[1].text.strip,
              reason: r.search('td')[3].text.strip
      end
    end
  end
end

p Time.now
excuses do |item|
  id= { 'excuse_id' => Digest::MD5.hexdigest("#{item[:date].gsub(/[^0-9,.]/, '')}#{item[:mop_id]}") }
  #p item.merge(id)
  ScraperWiki.save_sqlite(['excuse_id'],  item.merge(id))
end
p Time.now
