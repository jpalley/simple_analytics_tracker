class TrackingController < ApplicationController
  skip_before_action :verify_authenticity_token

  def identify
    identify_params = process_identify_params
    person = Person.find_or_initialize_by(uuid: identify_params[:uuid])

    identify_params[:properties]&.each do |key, value|
      person.properties[key] = value
    end

    if person.save
      render json: { status: "success" }, status: :created
    else
      render json: { status: "error", errors: person.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def event
    event_params = process_event_params
    event_params[:event_data][:browser_full_version] = browser.full_version
    event_params[:event_data][:browser_name] = browser.name
    event_params[:event_data][:browser_meta] = browser.meta
    event_params[:event_data][:browser_version] = browser.version
    if browser.bot?
      event_params[:event_data][:browser_bot] = true
      event_params[:event_data][:browser_bot_name] = browser.bot.name
    else
      event_params[:event_data][:browser_bot] = false
    end
    event_params[:event_data][:browser_mobile] = browser.device.mobile?
    event_params[:event_data][:browser_console] = browser.device.console?

    event_params[:event_data][:browser_device_name] = browser.device.name
    event_params[:event_data][:browser_device_id] = browser.device.id

    event_params[:event_data][:browser_platform_id] = browser.platform.id
    event_params[:event_data][:browser_platform_version] = browser.platform.version
    event_params[:event_data][:browser_platform_name] = browser.platform.name

    captured_headers = [
      "cf-ipcity", "cf-ipcountry", "cf-ipcontinent", "cf-iplongitude", "cf-iplatitude",
      "cf-region", "cf-region-code", "cf-metro-code", "cf-postal-code", "cf-timezone", "cf-connecting-ip",
      "referrer", :browser_platform_name, :browser_mobile, :browser_name, :js_user_agent
    ]

    captured_headers.each do |header|
      if request.headers[header]
        event_params[:event_data][header.gsub("-", "_")] = request.headers[header]
      end
    end


    event = Event.new(event_params)
    event.timestamp ||= Time.current # Ensure timestamp is set if not provided
    person = Person.find_or_create_by(uuid: event_params[:uuid])
    if event.event_type == "visit"
      # Update browser info and secondary_id

      # Update initial and latest URL parameters
      person.initial_params ||= {}
      person.latest_params ||= {}

      event_params[:event_data][:selected_params]&.each do |key, value|
        person.initial_params[key] ||= value
      end

      event_params[:event_data][:selected_params]&.each do |key, value|
        person.latest_params[key] = value
      end

      captured_headers.each do |header|
        if request.headers[header]
          person.latest_params[header.gsub("-", "_")] = request.headers[header]
          person.initial_params[header.gsub("-", "_")] ||= request.headers[header]
        end
      end


      if !person.save
        render json: { status: "error", errors: person.errors.full_messages }, status: :unprocessable_entity
        return
      end
    end
    if event.save
        render json: { status: "success" }, status: :created
    else
        render json: { status: "error", errors: event.errors.full_messages }, status: :unprocessable_entity
    end
  end

  private
  def process_identify_params
    params[:tracking].permit(
      :uuid,
      properties: {}
    )
  end

  def process_event_params
    params[:tracking].permit(
      :uuid,
      :event_type,
      :timestamp,
      event_data: {}
    )
  end
end
