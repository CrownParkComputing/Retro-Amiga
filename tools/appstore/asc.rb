#!/usr/bin/env ruby
# App Store Connect from the command line, for the parts the release needs.
#
#     tools/appstore/asc.rb status
#     tools/appstore/asc.rb builds
#     tools/appstore/asc.rb attach 31
#     tools/appstore/asc.rb shots APP_IPAD_PRO_3GEN_129 store/screenshots/*.png
#     tools/appstore/asc.rb price GBR 2.99
#     tools/appstore/asc.rb blockers
#     tools/appstore/asc.rb submit
#
# Credentials come from the environment so nothing account-specific lives in
# the repo. Put them in ~/.config/appstore.env, which this reads if present:
#
#     ASC_KEY_ID=XXXXXXXXXX
#     ASC_ISSUER_ID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
#     ASC_BUNDLE_ID=com.example.app
#
# The .p8 itself stays at ~/.appstoreconnect/private_keys/AuthKey_<KEYID>.p8
# and is never read by anything but spaceship.
#
# WHY THIS EXISTS. Two of the gates that block a first submission -- app
# pricing and the App Privacy answers -- are invisible on the version page and
# only surface as a generic "not in valid state" when you try to submit. The
# reason is buried in errors[0].meta.associatedErrors, which spaceship does not
# surface at all. `blockers` digs it out; see docs/APP_STORE_RELEASE.md.

require "json"
require "net/http"
require "base64"

# Use whatever fastlane is installed rather than pinning a version, since the
# Homebrew path carries one and it moves on every upgrade.
# The second glob matters: spaceship is not a sibling gem, it is vendored
# inside the fastlane gem at fastlane-<v>/spaceship/lib.
gem_roots = Dir["/opt/homebrew/Cellar/fastlane/*/libexec/gems/*/lib"] +
            Dir["/opt/homebrew/Cellar/fastlane/*/libexec/gems/fastlane-*/*/lib"] +
            Dir["/usr/local/Cellar/fastlane/*/libexec/gems/*/lib"] +
            Dir["/usr/local/Cellar/fastlane/*/libexec/gems/fastlane-*/*/lib"]
abort("fastlane not found -- brew install fastlane") if gem_roots.empty?
$LOAD_PATH.unshift(*gem_roots)
require "spaceship"

# ---------------------------------------------------------------- credentials

env_file = File.expand_path("~/.config/appstore.env")
if File.exist?(env_file)
  File.readlines(env_file).each do |line|
    next if line.strip.empty? || line.strip.start_with?("#")
    k, v = line.strip.split("=", 2)
    ENV[k] ||= v
  end
end

def need(name)
  ENV[name] || abort("#{name} not set (see ~/.config/appstore.env)")
end

KEY_ID    = need("ASC_KEY_ID")
ISSUER_ID = need("ASC_ISSUER_ID")
BUNDLE_ID = ENV["ASC_BUNDLE_ID"] || abort("ASC_BUNDLE_ID not set")

TOKEN = Spaceship::ConnectAPI::Token.create(
  key_id: KEY_ID, issuer_id: ISSUER_ID,
  filepath: File.expand_path("~/.appstoreconnect/private_keys/AuthKey_#{KEY_ID}.p8"))
Spaceship::ConnectAPI.token = TOKEN

APP = Spaceship::ConnectAPI::App.find(BUNDLE_ID) or abort("no app record for #{BUNDLE_ID}")

# Raw REST, for the endpoints spaceship has no model for and -- more
# importantly -- for the error payloads it throws away.
def api(verb, path, body = nil)
  uri = URI("https://api.appstoreconnect.apple.com/#{path}")
  klass = { "GET" => Net::HTTP::Get, "POST" => Net::HTTP::Post,
            "PATCH" => Net::HTTP::Patch, "DELETE" => Net::HTTP::Delete }.fetch(verb)
  req = klass.new(uri)
  req["Authorization"] = "Bearer #{TOKEN.text}"
  req["Content-Type"] = "application/json"
  req.body = body.to_json if body
  res = Net::HTTP.start(uri.host, uri.port, use_ssl: true) { |h| h.request(req) }
  [res.code.to_i, (JSON.parse(res.body) rescue res.body)]
end

def edit_version
  APP.get_edit_app_store_version or
    abort("no editable version -- live is #{APP.get_live_app_store_version&.version_string}")
end

# ------------------------------------------------------------------- commands

def cmd_status
  v = edit_version
  puts "#{APP.name} (#{APP.id})  #{BUNDLE_ID}"
  puts "version: #{v.version_string}  state=#{v.app_store_state}"
  puts "build:   #{v.build&.version || '(none attached)'}"
  d = begin v.fetch_app_store_review_detail rescue nil end
  puts "contact: #{d ? "#{d.contact_first_name} #{d.contact_last_name} #{d.contact_phone}" : 'NOT SET'}"
  puts "notes:   #{d&.notes ? "#{d.notes.to_s.length} chars" : 'NOT SET'}"
  v.get_app_store_version_localizations.each do |l|
    puts "#{l.locale}: desc=#{l.description ? 'set' : 'MISSING'} " \
         "keywords=#{l.keywords ? 'set' : 'MISSING'} " \
         "support=#{l.support_url ? 'set' : 'MISSING'}"
    l.get_app_screenshot_sets.each do |s|
      states = s.app_screenshots.map { |sh| sh.asset_delivery_state&.dig("state") }.tally
      puts "   #{s.screenshot_display_type}: #{s.app_screenshots.size} #{states.inspect}"
    end
  end
end

def cmd_builds
  builds = APP.get_builds(includes: "preReleaseVersion", limit: 200)
  nums = builds.map { |b| b.version.to_i }
  puts "highest=#{nums.max}  next=#{nums.max.to_i + 1}"
  builds.first(8).each { |b| puts "   #{b.version}  #{b.processing_state}" }
end

def cmd_attach(want)
  abort("usage: attach <build-number>") unless want
  b = APP.get_builds(includes: "preReleaseVersion", limit: 200)
         .find { |x| x.version.to_s == want.to_s }
  abort("build #{want} not found") unless b
  abort("build #{want} is #{b.processing_state}, not VALID") unless b.processing_state == "VALID"
  v = edit_version
  puts "attaching build #{b.version} to #{v.version_string}"
  v.select_build(build_id: b.id)
  puts "attached: #{APP.get_edit_app_store_version.build&.version}"
end

# Display types are Apple's, not the marketing names. There is no
# APP_IPHONE_69: Apple folds 6.9" devices into APP_IPHONE_67, which accepts
# 1320x2868 without complaint. iPad 13" is APP_IPAD_PRO_3GEN_129.
def cmd_shots(display_type, files)
  abort("usage: shots <DISPLAY_TYPE> <file.png>...") if display_type.nil? || files.empty?
  files.each do |f|
    abort("#{f}: not found") unless File.exist?(f)
    # Alpha is the single most common screenshot rejection and the upload
    # itself does not catch it -- processing does, silently, much later.
    out = `sips -g hasAlpha #{f.shellescape} 2>/dev/null`
    abort("#{f} has an alpha channel -- run tools/flatten-screenshot.swift") if out.include?("hasAlpha: yes")
  end
  v = edit_version
  loc = v.get_app_store_version_localizations.find { |l| l.locale == "en-GB" } ||
        v.get_app_store_version_localizations.first
  set = loc.get_app_screenshot_sets.find { |s| s.screenshot_display_type == display_type }
  if set
    puts "#{display_type}: clearing #{set.app_screenshots.size}"
    set.app_screenshots.each(&:delete!)
    set = loc.get_app_screenshot_sets.find { |s| s.screenshot_display_type == display_type }
  else
    puts "creating #{display_type}"
    set = loc.create_app_screenshot_set(attributes: { screenshotDisplayType: display_type })
  end
  files.sort.each do |f|
    print "   #{File.basename(f)} ... "
    set.upload_screenshot(path: f, wait_for_processing: true)
    puts "ok"
  end
end

# A brand-new app has no price schedule, and nothing says so until submission
# fails. Free apps need one too -- pass 0.
def cmd_price(territory, amount)
  abort("usage: price <TERRITORY> <AMOUNT>   e.g. price GBR 2.99") if territory.nil? || amount.nil?
  want = amount.to_f
  _, body = api("GET", "v1/apps/#{APP.id}/appPricePoints?filter[territory]=#{territory}&limit=200")
  point = (body["data"] || []).find { |p| (p.dig("attributes", "customerPrice").to_f - want).abs < 0.001 }
  unless point
    near = (body["data"] || []).map { |p| p.dig("attributes", "customerPrice").to_f }
                               .sort_by { |a| (a - want).abs }.first(5)
    abort("no #{territory} price point at #{want}; nearest: #{near.inspect}")
  end
  code, resp = api("POST", "v1/appPriceSchedules", {
    data: { type: "appPriceSchedules",
            relationships: {
              app: { data: { type: "apps", id: APP.id } },
              baseTerritory: { data: { type: "territories", id: territory } },
              manualPrices: { data: [{ type: "appPrices", id: "${new-price}" }] } } },
    included: [{ type: "appPrices", id: "${new-price}",
                 attributes: { startDate: nil, endDate: nil },
                 relationships: { appPricePoint: { data: { type: "appPricePoints", id: point["id"] } } } }] })
  if code == 201
    puts "price set: #{want} #{territory} (base territory #{territory})"
  else
    abort("price failed [#{code}] #{(resp['errors'] || []).map { |e| e['detail'] }.join('; ')}")
  end
end

def review_submission
  _, body = api("GET", "v1/apps/#{APP.id}/reviewSubmissions?limit=20")
  open = (body["data"] || []).find do |s|
    %w[READY_FOR_REVIEW].include?(s.dig("attributes", "state")) &&
      s.dig("attributes", "submittedDate").nil?
  end
  return open["id"] if open
  code, resp = api("POST", "v1/reviewSubmissions", {
    data: { type: "reviewSubmissions", attributes: { platform: "IOS" },
            relationships: { app: { data: { type: "apps", id: APP.id } } } } })
  abort("could not create submission [#{code}]") unless code == 201
  resp.dig("data", "id")
end

# The whole point of this file. A refused submission returns a generic
# "not in valid state"; the actual reasons are nested in the error's meta.
def add_version_item(sub, ver)
  api("POST", "v1/reviewSubmissionItems", {
    data: { type: "reviewSubmissionItems",
            relationships: {
              reviewSubmission: { data: { type: "reviewSubmissions", id: sub } },
              appStoreVersion: { data: { type: "appStoreVersions", id: ver } } } } })
end

def report_blockers(body)
  assoc = body.dig("errors", 0, "meta", "associatedErrors") || {}
  if assoc.empty?
    puts "  #{(body['errors'] || []).map { |e| "#{e['code']}: #{e['detail']}" }.join(' | ')}"
  else
    assoc.each { |where, list| list.each { |e| puts "  #{where}  #{e['code']}\n      #{e['title']}" } }
  end
end

def cmd_blockers
  v = edit_version
  code, body = add_version_item(review_submission, v.id)
  if code == 201
    puts "no blockers -- version is queued in the submission, run `submit` to send it"
  else
    puts "blocked [#{code}]:"
    report_blockers(body)
  end
end

def cmd_submit
  v = edit_version
  puts "submitting #{v.version_string} (build #{v.build&.version || 'NONE'})"
  abort("no build attached") if v.build.nil?
  sub = review_submission

  # Apple's own answers propagate asynchronously: publishing the App Privacy
  # form and immediately adding the version fails, then succeeds ~25s later.
  # Retry rather than reporting a blocker that has already been cleared.
  code = nil
  3.times do |i|
    code, body = add_version_item(sub, v.id)
    break if code == 201
    if i == 2
      puts "blocked [#{code}]:"
      report_blockers(body)
      abort
    end
    sleep 25
  end

  code, body = api("PATCH", "v1/reviewSubmissions/#{sub}",
                   { data: { type: "reviewSubmissions", id: sub, attributes: { submitted: true } } })
  abort("submit failed [#{code}] #{body.inspect[0, 300]}") if code >= 400
  puts "submitted #{body.dig('data', 'attributes', 'submittedDate')}"
  puts "state: #{APP.get_edit_app_store_version&.app_store_state}"
end

# ---------------------------------------------------------------------- entry

require "shellwords"
cmd, *rest = ARGV
case cmd
when "status"   then cmd_status
when "builds"   then cmd_builds
when "attach"   then cmd_attach(rest[0])
when "shots"    then cmd_shots(rest[0], rest[1..] || [])
when "price"    then cmd_price(rest[0], rest[1])
when "blockers" then cmd_blockers
when "submit"   then cmd_submit
else
  puts <<~USAGE
    usage: asc.rb <command>

      status                    version, build, metadata and screenshot state
      builds                    uploaded builds, highest and next free number
      attach <n>                attach build n to the editable version
      shots <TYPE> <png>...     replace a screenshot set (checks for alpha)
      price <TERRITORY> <AMT>   create the price schedule (0 for free)
      blockers                  why the version cannot be submitted
      submit                    attach to a review submission and send it

    Reads ASC_KEY_ID, ASC_ISSUER_ID and ASC_BUNDLE_ID from the environment or
    ~/.config/appstore.env. Set ASC_BUNDLE_ID per app:

      ASC_BUNDLE_ID=com.example.other tools/appstore/asc.rb status
  USAGE
  exit 64
end
