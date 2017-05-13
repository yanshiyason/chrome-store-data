# What is it?

It's a Ruby script which downloads data of the add-ons on the [google chrome store](https://chrome.google.com/webstore/category/extensions).

# Why?

I was doing research to see what kind of add-ons were popular in the chrome store but I couldn't find that data anywhere..

# How to use it?

install the dependencies (`mechanize`, `activerecord`, `sqlite3`):

```bash
bundle install
```

make the script executable:

```bash
chmod +x ./chrome_store.rb
```

Run the program:

```bash
bundle exec ./chrome_store.rb --help

    valid options are:

    -d    (downloads all data to sqlite)
    -c    (generates csv from data in sqlite)
```

Download the data with:
(this will take 10 to 15 mins)
```bash
bundle exec ./chrome_store.rb -d
```

Write the data to csv with:
```bash
bundle exec ./chrome_store.rb -c
```


Here is an example of the generated data:

https://docs.google.com/spreadsheets/d/1L9lLkUdQsHnQOO-EgmLrp7vaJ2nC3RrzHWEFHkBlXP4/edit#gid=0
