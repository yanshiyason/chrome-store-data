#!/usr/bin/env ruby

require 'active_record'
require 'sqlite3'

ActiveRecord::Base.establish_connection(
  adapter: 'sqlite3',
  database: 'chrome_store_stats'
)

unless ActiveRecord::Base.connection.data_sources.include?('chrome_store_items')
  ActiveRecord::Schema.define do
    create_table :chrome_store_items do |table|
      table.column :chrome_id, :string     # id on chrome store
      table.column :title, :string         # title on chrome store
      table.column :downloads, :integer    # number of downloads
      table.column :description, :string   # description on chrome store
      table.column :category, :string      # machine readable category name
      table.column :category_name, :string # human readable category name
      table.column :rating, :float         # average rating
      table.column :user_ratings, :integer # number of users who rated
      table.column :pricing, :string       # pricing type
    end
  end
end

# Extend String with a simple utilty method
module StringExtensions
  refine String do
    def strip_commas
      tr(',', '')
    end
  end
end

# main module
module ChromeStore
  require 'mechanize'
  require 'json'

  def self.table_name_prefix
    'chrome_store_'
  end

  # An item in the chrome store (app, extension, game, etc)
  class Item < ActiveRecord::Base
    using StringExtensions

    def to_array
      as_json.map { |_k, v| v }
    end

    # coerce strings with commas to integers
    # ex: "1,304,123" -> 1304123
    def downloads=(val)
      downloads = val.is_a?(String) ? val.strip_commas.to_i : val
      write_attribute(:downloads, downloads)
    end
  end

  # Base class for all chrome store pages
  class Page
    def agent
      @agent ||= ::Mechanize.new
    end

    def url
      raise 'please override me'
    end

    def page
      @page ||= agent.get url
    end
  end

  # Top page of the chrome webstore
  class RootPage < Page
    def url
      'https://chrome.google.com/webstore'
    end

    def categories
      page.body.scan(%r{(ext\/(?!free).+?)\"}).flatten.uniq
    end
  end

  # Category page of the chrome webstore
  class CategoryPage < Page
    attr_reader :category
    def initialize(category:)
      @category = category
    end

    def url
      'https://chrome.google.com/webstore/category/' + category
    end
  end

  # This is the endpoint which gets requested by ajax when scrolling
  # down the chrome store to load more items
  # it needs a category, and an offset.
  #
  # The offset is initially nil. After each request, the server returns the
  # next offset wihch must be placed in the next request's parameters.
  class ItemPage < Page
    attr_reader :category, :count, :offset
    def initialize(category:, count: nil, offset: nil)
      @category = category
      @count = count || 75
      @offset = offset
    end

    def url
      'https://chrome.google.com/webstore/ajax/item?' +
        URI.encode_www_form(params)
    end

    def params
      @params ||= set_params
    end

    def page
      puts "requesting #{params.to_json}"
      agent.post(url)
    end

    def data
      @data ||= JSON.parse(
        # for some reason, JSON data starts after first \n\n
        page.body.split("\n\n")[-1]
      )
    end

    def next_offset
      offset_index = [0, 1, 4]
      data.dig(*offset_index)
    end

    def items_index
      [0, 1, 1]
    end

    def items
      data.dig(*items_index)
    end

    private

    def set_params
      params = initial_params
      params[:count] = count if count
      params[:token] = offset if offset
      params
    end

    def initial_params
      {
        hl: 'en-US',
        gl: 'JP',
        pv: 20170206,
        mce: 'atf,eed,pii,rtr,rlb,gtc,hcn,svp,wtd,c3d,ncr,ctm,ac,hot,mac,fcf,rma',
        count: 28,
        marquee: true,
        category: category,
        sortBy: 0,
        container: 'CHROME',
        rt: 'j',
      }
    end
  end

  # Spawns new ItemPages with incremental offset
  # and saves the items returned by them.
  class Downloader
    attr_accessor :count, :offset
    def initialize
      puts 'starting download..'
      @count = nil
      @offset = nil
    end

    def categories
      @categories ||= RootPage.new.categories
    end

    def download_all
      categories.each do |category|
        download(category: category)
      end
      puts 'finished downloading'
    end

    def download(category:)
      loop do
        item_page = ItemPage.new(category: category, count: count, offset: offset)

        self.offset = item_page.next_offset
        self.count ||= 75

        puts "found #{item_page.items.count} items"

        item_page.items.each do |item|
          create_item(item)
        end

        puts "total items in db: #{Item.count}"
      end
    rescue Mechanize::ResponseCodeError => e
      puts [category, e.class, e.message].join
      puts 'probably no more items - going to next category'
      self.offset, self.count = nil
    end

    private

    ITEM_INDEXES = {
      id: 0,
      title: 1,
      downloads: 23,
      description: 6,
      category: 9,
      category_name: 10,
      rating: 12,
      user_ratings: 22,
      pricing: 30,
    }

    def create_item(page_item)
      chrome_item =
        Item.find_or_initialize_by(
          chrome_id: page_item[ITEM_INDEXES[:id]]
        )

      chrome_item.attributes = {
        title:         page_item[ITEM_INDEXES[:title]],
        downloads:     page_item[ITEM_INDEXES[:downloads]],
        description:   page_item[ITEM_INDEXES[:description]],
        category:      page_item[ITEM_INDEXES[:category]],
        category_name: page_item[ITEM_INDEXES[:category_name]],
        rating:        page_item[ITEM_INDEXES[:rating]],
        user_ratings:  page_item[ITEM_INDEXES[:user_ratings]],
        pricing:       page_item[ITEM_INDEXES[:pricing]],
      }

      chrome_item.save!
    end
  end

   # writes all ChromeStore::Items to csv file.
  class CSVWriter
    require 'csv'

    class << self
      def path
        './chrome_store_data.csv'
      end

      def write
        puts "writing file to #{path}"
        CSV.open(path, 'w') do |csv|
          csv << ChromeStore::Item.column_names
          ChromeStore::Item.find_each do |item|
            csv << item.to_array
          end
        end
      end
    end
  end
end

case ARGV[0]
when '-d'
  puts 'Download starting'
  ChromeStore::Downloader.new.download_all
when '-c'
  puts 'generating csv'
  ChromeStore::CSVWriter.write
when nil
  nil
else
  puts <<-MSG
    valid options are:

    -d    (downloads all data to sqlite)
    -c    (generates csv from data in sqlite)
  MSG
end
