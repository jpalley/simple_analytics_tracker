class HubspotClient
  include HTTParty
  base_uri "https://api.hubapi.com"

  def contacts_by_utk(utks)
    utks = utks.map { |u| "utk=#{u}" }.join("&")
    response = self.class.get("/contacts/v1/contact/byUtk/batch/?#{utks}", {
      headers: {
        "Authorization" => "Bearer #{ENV['HUBSPOT_ACCESS_TOKEN']}"
      }
    })
    raise "Hubspot API Error" if !response.success?
    return {} unless response.success?
    puts "response.parsed_response: #{response.parsed_response.inspect}"
    # Convert response to a hash with utk as keys for easier lookup
    result = {}
    response.parsed_response.each do |utk, contact|
      result[utk] = contact
    end
    result
  end
end
