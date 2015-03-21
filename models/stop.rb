class Stop

  attr_accessor :data, :time

  def initialize(stop_id)
    @stop_id = stop_id
    @time = Time.now
  end

  REFRESH_PERIOD = 60 # seconds

  @@instances = {}

  def self.for_id(stop_id)
    if stop = @@instances[stop_id]
      now = Time.now
      if now - stop.time > REFRESH_PERIOD
        puts "reloading stop data"
        @@instances[stop_id] = self.new(stop_id).get_data
      else
        puts "using old instance"
        stop
      end
    else
      puts "loading new stop data"
      @@instances[stop_id] = self.new(stop_id).get_data
    end
  end

  STOP_INFO_URI = 
    'http://api.pugetsound.onebusaway.org/api/where/schedule-for-stop/%s.json?key=%s'

  ROUTE_INFO_URI =
    'http://api.pugetsound.onebusaway.org/api/where/route/%s.json?key=%s'

  KEY = IO.read('oba_rest_key.txt').strip

  def get_data
    url = URI.parse(sprintf(STOP_INFO_URI, @stop_id, KEY))
    req = Net::HTTP::Get.new(url.to_s)
    res = Net::HTTP.start(url.host, url.port) { |http|
      http.request(req)
    }

    if /^4/.match(res.code)
      raise "got a 4*"

    else
      body_blob = JSON.load(res.body)

      if data = body_blob['data']
        raw_routes = data['entry']['stopRouteSchedules']

        routes = raw_routes.each_with_object(Hash.new) do |route_blob, routes|
          route_id = route_blob['routeId']

          # grab the actual route number
          route_url = URI.parse(sprintf(ROUTE_INFO_URI, route_id, KEY))
          route_req = Net::HTTP::Get.new(route_url.to_s)
          route_res = Net::HTTP.start(route_url.host, route_url.port) do |http| 
            http.request(route_req)
          end

          route_info_blob = JSON.load(route_res.body)

          routes[route_id] = {}

          routes[route_id]['route_number'] =
            if route_info = route_info_blob['data']
              route_info['entry']['shortName']
            else
              nil
            end

          # arrange stop time data
          stop_times = route_blob['stopRouteDirectionSchedules'].first['scheduleStopTimes']

          stops = stop_times.each_with_object(Array.new) do |stop_time, stops|
            stops << Time.at(stop_time['arrivalTime'].to_s.slice(0..-4).to_i)
          end

          headsign = route_blob['stopRouteDirectionSchedules'].first['tripHeadsign']

          routes[route_id].merge!(
            "headsign" => headsign,
            "stops" => stops
          )

        end

        self.data = routes
      else
        raise "no data returned!"
      end

    end

    self
  end

end
