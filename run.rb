require 'rest-client'
require 'json'
require 'yaml'
require 'pp'
require 'active_support/core_ext/hash/slice'


class NameApi
  class << self

    attr_accessor :token

    def config
      @config ||= YAML.load(File.read('config.yml'))['production']
    end

    def api_website
      @config['api_website']
    end

    def login
      username = config['username']
      api_token = config['api_token']
      response = RestClient.post(api_website + '/api/login', {username: username, api_token: api_token}.to_json)
      result = JSON.load(response.body)
      self.token = result['session_token']
    end

    def domain_list
      response = RestClient.get(api_website + '/api/domain/list', 'Api-Session-Token' => self.token)
      result = JSON.load(response.body)
    end

    def hello
      response = RestClient.get(api_website + '/api/hello', 'Api-Session-Token' => self.token)
      result = JSON.load(response.body)
    end

    def dns_records_list(domain)
      response = RestClient.get(api_website + '/api/dns/list/'+domain, 'Api-Session-Token' => self.token)
      result = JSON.load(response.body)
    end

    def dns_records_create(domain, params)
      response = RestClient.post(api_website + '/api/dns/create/'+domain,
                                 params.to_json,
                                 'Api-Session-Token' => self.token)
      result = JSON.load(response.body)
    end

    def dns_records_delete(domain, record_id)
      response = RestClient.post(api_website + '/api/dns/delete/'+domain,
                                 {record_id: record_id}.to_json,
                                 'Api-Session-Token' => self.token)
      result = JSON.load(response.body)
    end

    def save_hosts_to_file(domain, filename)
      data = read_hosts(domain).map{ |r| r.slice('name', 'content') }
      File.write(filename, YAML.dump('hosts' => data))
    end

    def read_hosts(domain)
      NameApi.dns_records_list(domain)['records'].
        sort_by{|r| r['content']}.map do |r|
        r['name'] = r['name'].gsub!(".#{domain}", '')
        r
      end
    end

    def save_file_to_hosts(domain, filename)
      current_mapping = {}
      NameApi.read_hosts(domain).each do |r|
        current_mapping[r['name']] = {op: :delete, content: r['content'], record_id: r['record_id']}
      end
      PP.pp current_mapping

      YAML.load(File.read(filename))['hosts'].each do |r|
        v = current_mapping[r['name']]
        if !v
          current_mapping[r['name']] = {op: :create, content: r['content']}
        elsif v[:content] != r['content']
          v[:op] = :update
          v[:content] = r['content']
        else
          v[:op] = :ignore
        end
      end
      changes = current_mapping.select{ |k, v| v[:op] != :ignore}
      puts "changes:"
      PP.pp changes

      changes.each do |name, v|
        content = v[:content]
        case v[:op]
        when :create
          data = {hostname: name, type: 'A', content: content,
                  ttl: 300, priority: 10}
          puts NameApi.dns_records_create(domain, data)
        when :delete
          puts NameApi.dns_records_delete(domain, v[:record_id])
        when :update
          puts NameApi.dns_records_delete(domain, v[:record_id])
          data = {hostname: name, type: 'A', content: content,
                  ttl: 300, priority: 10}
          puts NameApi.dns_records_create(domain, data)
        end
      end
    end
    
  end
end

def example
  NameApi.login
  NameApi.hello
  NameApi.domain_list
  NameApi.dns_records_list('test.click')
  NameApi.dns_records_create('test.click',
                             hostname: 'test', type: 'A', content: '192.168.1.2',
                             ttl: 300, priority: 10)
  
  NameApi.save_hosts_to_file('test.click', 'hosts1.yml')
  NameApi.save_file_to_hosts('test.click', 'hosts.yml')
end
