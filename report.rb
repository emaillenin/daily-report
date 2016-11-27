require 'sendgrid-ruby'
require 'mysql2'
require 'yaml'

class Mailer
  include SendGrid

  def send_mail
    mail_config = Config.get_config['mail']
    today = DateTime.now.strftime('%d.%m.%Y')
    mail = Mail.new
    mail.from = Email.new(email: mail_config['from_mail'], name: 'Lessel')
    mail.subject = "Lessel Daily Report for #{today}"
    personalization = Personalization.new
    personalization.to = Email.new(email: mail_config['to_mail'])
    mail.personalizations = get_substitutions(personalization)
    mail.contents = Content.new(type: 'text/html', value: 'Thank You.')
    mail.template_id = mail_config['template_id']

    sg = SendGrid::API.new(api_key: mail_config['api_key'])
    puts mail.to_json
    begin
      response = sg.client.mail._('send').post(request_body: mail.to_json)
    rescue Exception => e
      $stderr.write(e.message)
    end
  end

  def get_substitutions(personalization)
    queries = Queries.new
    personalization.substitutions = Substitution.new(key: '-cash-sales-', value: number_to_indian_currency(queries.get_cash_sales))
    personalization.substitutions = Substitution.new(key: '-credit-sales-', value: number_to_indian_currency(queries.get_credit_sales))
    queries.get_top_3_customers.each_with_index do |top_customer, index|
      personalization.substitutions = Substitution.new(key: "-customer-#{index+1}-name-", value: top_customer['cust_name'])
      personalization.substitutions = Substitution.new(key: "-customer-#{index+1}-sales-", value: top_customer['amount'])
    end
    queries.get_top_3_products.each_with_index do |top_product, index|
      personalization.substitutions = Substitution.new(key: "-product-#{index+1}-name-", value: top_product['prod_name'])
      personalization.substitutions = Substitution.new(key: "-product-#{index+1}-sales-", value: top_product['amount'])
    end
    personalization
  end

  def number_to_indian_currency(number)
    if number != nil
      string = number.to_s.split('.')
      number = string[0].gsub(/(\d+)(\d{3})$/) { p = $2; "#{$1.reverse.gsub(/(\d{2})/, '\1,').reverse},#{p}" }
      number = number.gsub(/^,/, '') + '.' + string[1] if string[1] # remove leading comma
      number = number[1..-1] if number[0] == 44
    else
      number = 0
    end
    "₹ #{number}"
  end
end


class Queries
  CASH_SALES = "select sum(BILL_TOTAL_AMOUNT) as amount from bill bi join book bo on bi.book_id = bo.book_id where bo.book_code = 'SCA' and bill_date = current_date"
  CREDIT_SALES = "select sum(BILL_TOTAL_AMOUNT) as amount from bill bi join book bo on bi.book_id = bo.book_id where bo.book_code = 'SCR' and bill_date = current_date"
  TOP_3_CUSTOMERS = "select cust_name, sum(BILL_TOTAL_AMOUNT) as amount from bill bi join book bo on bi.book_id = bo.book_id join customer c on c.cust_id = bi.cust_id where bo.book_code in ('SCA', 'SCR') and bill_date = current_date group by 1 order by 2 desc limit 3"
  TOP_3_PRODUCTS = "select p.prod_name, sum(AMOUNT) as amount from bill bi join bill_detail bd on bi.bill_id = bd.bill_id join book bo on bi.book_id = bo.book_id join product p on p.prod_id = bd.prod_id where bo.book_code in ('SCA', 'SCR') and bill_date = current_date group by 1 order by 2 desc limit 3"

  def initialize
    db_config = Config.get_config['database']
    @db_client = Mysql2::Client.new(db_config)
  end

  def get_cash_sales
    @db_client.query(CASH_SALES).first['amount'] || 0
  end

  def get_credit_sales
    @db_client.query(CREDIT_SALES).first['amount'] || 0
  end

  def get_top_3_customers
    @db_client.query(TOP_3_CUSTOMERS)
  end

  def get_top_3_products
    @db_client.query(TOP_3_PRODUCTS)
  end
end

class Config
  def self.get_config
    config_file = "#{File.expand_path(File.dirname(__FILE__))}/settings.yml"
    YAML.load_file(config_file)
  end
end

mailer = Mailer.new
mailer.send_mail
