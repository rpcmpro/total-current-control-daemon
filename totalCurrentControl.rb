require 'em-http-request'
require 'json'
require 'optparse'

class TotalCurrentControl
  @@logfile = 'totalCurrentControl.log'
  @@verbose = false
  @@daemonize = false
  @@testMode = false
  @@workingDirectory = Dir.pwd
  @@loggingToFile = true
  @@version = "0.1.0"
  @@devicesCache = {}
  @@devicesNames = {}
  @@devicesGroups = {}
  @@groups = {}

  def self.readConfig
    @@optionsParser = OptionParser.new do |opts|
      opts.banner = "\nTotal Current Control Daemon version #{@@version} for RPCM ME (http://rpcm.pro)\n\nUsage: totalCurrentControl.rb [options]"

      opts.on("-d", "--daemonize", "Daemonize and return control") do |v|
        @@daemonize = v
      end

      opts.on("-l", "--[no-]log", "Save log to file") do |v|
        @@loggingToFile = v
      end

      opts.on("-t", "--test-mode", "Test mode - don't really turn on/turn off ports - just log intentions") do |v|
        @@testMode = v
      end

      opts.on("-v", "--verbose", "Run verbosely") do |v|
        @@verbose = v
      end

      opts.on("-w", "--working-directory PATH", "Specify working directory (default current directory)") do |v|
        @@workingDirectory = v
      end
    end

    @@optionsParser.parse!

    configText = File.read "#{@@workingDirectory}/totalCurrentControl.conf"

    @@configHash = JSON.parse configText

    if @@configHash.class != Hash
      log text: "#{Time.now} Error parsing config. Exiting..."
      exit 1
    end

    populateDeviceCachesWithAddresses

    if @@verbose
      log text: @@devicesCache
    end
  end

  def self.daemonize
    @@daemonize
  end

  def self.testMode
    @@testMode
  end
  
  def self.verbose
    @@verbose
  end

  def self.configHash
    @@configHash
  end

  def self.devicesCache
    @@devicesCache
  end

  def self.logPrint text:
    print text

    if @@loggingToFile
      f = File.open "#{@@workingDirectory}/#{@@logfile}", 'a'
      f.print text
      f.close
    end
  end

  def self.log text:
    logPrint text: "#{text}\n"
  end

  def self.populateDeviceCachesWithAddresses
    @@configHash.each do |groupName, group|
      if @@groups.has_key? groupName
        log text: "duplicate group #{groupName} in config"
        exit 1
      else
        @@groups[groupName] = {}
        @@groups[groupName]['overTotalLimitSince'] = Time.now
        @@groups[groupName]['overTotalLimit'] = false
        @@groups[groupName]['overTotalLimitStabilized'] = false
        @@groups[groupName]['enoughAvailableAmpsSince'] = Time.now
        @@groups[groupName]['enoughAvailableAmps'] = false
        @@groups[groupName]['enoughAvailableAmpsStabilized'] = false
        @@groups[groupName]['currentTotalAmps'] = 0
        @@groups[groupName]['survivalPriorities'] = {}
      end
      if group.has_key? 'RPCMs'
        group['RPCMs'].each do |rpcmName, rpcm|
          if not rpcm.has_key? 'api_address'
            log text: "api_address is mandatory, not found for #{rpcmName}"
            exit 1
          end
          apiAddress = rpcm['api_address']
          if @@devicesCache.has_key? apiAddress
            log text: "duplicate address #{apiAddress} in config"
            exit 1
          else
            @@devicesCache[apiAddress] = {}
            @@devicesNames[apiAddress] = rpcmName
            @@devicesGroups[apiAddress] = groupName
          end

          if rpcm.has_key? 'outlets'
            rpcm['outlets'].each do |outletNumber, outletHash|
              survivalPriority = outletHash['survivalPriority'] rescue nil
              defaultState = outletHash['defaultState'] rescue nil
              comment = outletHash['comment'] rescue nil
              next if survivalPriority == nil
              if survivalPriority.class == Integer
                if not @@groups[groupName]['survivalPriorities'].has_key? survivalPriority
                  @@groups[groupName]['survivalPriorities'][survivalPriority] = {}
                end
                survivalPriorityInGroup = @@groups[groupName]['survivalPriorities'][survivalPriority]
                survivalPriorityKey = "#{outletNumber}@#{rpcmName}"
                survivalPriorityInGroup[survivalPriorityKey] = {}
                survivalPriorityInGroup[survivalPriorityKey]['api_address'] = apiAddress
                survivalPriorityInGroup[survivalPriorityKey]['outletNumber'] = outletNumber
                survivalPriorityInGroup[survivalPriorityKey]['comment'] = comment
                survivalPriorityInGroup[survivalPriorityKey]['defaultState'] = defaultState
              else
                log text: "survivalPriority has to be Integer - now #{survivalPriority}"
                exit 1
              end
            end
          end
        end
      end
    end
  end

  def self.limitAmps groupName:
    @@configHash[groupName]['limitAmps'] rescue nil
  end

  def self.delayBeforeTurnOffSeconds groupName:
    @@configHash[groupName]['delayBeforeTurnOffSeconds'] rescue nil
  end

  def self.tryToTurnOnWhenAvailableAmps groupName:
    @@configHash[groupName]['tryToTurnOnWhenAvailableAmps'] rescue nil
  end

  def self.delayBeforeTryToTurnOnSeconds groupName:
    @@configHash[groupName]['delayBeforeTryToTurnOnSeconds'] rescue nil
  end

  def self.currentTotalAmps groupName:
    @@groups[groupName]['currentTotalAmps'] rescue nil
  end

  def self.setUpDeviceCacheRegularUpdate
    @@devicesCache.each_key do |apiAddress|
      EM.add_periodic_timer(2) do
        RPCMAPIControl.getCachedStatus(apiAddress: apiAddress) do |jsonHash|
          EM.next_tick do
            @@devicesCache[apiAddress] = jsonHash
          end
        end
      end
    end
  end

  def self.listOfDevices
    result = ''
    @@devicesNames.each do |apiAddress, rpcmName|
      result += "#{apiAddress} (#{rpcmName})\n"
    end

    return result
  end

  def self.listOfSurvivalPriorities
    result = "List Of Survival Priorities For Groups:\n"

    @@groups.each do |groupName, group|
      result += "[#{groupName}]\n"
      group['survivalPriorities'].keys.sort.each do |priority|
        result += "#{priority}: ["
        first = true
        group['survivalPriorities'][priority].each do |key, hash|
          result += ', ' if first != true
          result += "#{key} (#{hash['api_address']} - #{hash['comment']})"
          first = false
        end
        result += "]\n"
      end
    end

    return result
  end

  def self.milliampsFromCacheFor rpcm:, outlet:
    @@devicesCache[rpcm]['ats']['channels']["#{outlet}"]['instantMilliamps'] rescue 0
  end

  def self.adminStateFromCacheFor rpcm:, outlet:
    @@devicesCache[rpcm]['ats']['channels']["#{outlet}"]['adminState'] rescue nil
  end

  def self.actualStateFromCacheFor rpcm:, outlet:
    @@devicesCache[rpcm]['ats']['channels']["#{outlet}"]['adminState'] rescue nil
  end

  def self.circuitBreakerFiredStateFromCacheFor rpcm:, outlet:
    @@devicesCache[rpcm]['ats']['channels']["#{outlet}"]['circuitBreakerFiredState'] rescue nil
  end

  def self.overcurrentTurnOffFiredStateFromCacheFor rpcm:, outlet:
    @@devicesCache[rpcm]['ats']['channels']["#{outlet}"]['overcurrentTurnOffFiredState'] rescue nil
  end

  def self.updateTotalsForGroups
    if @@groups == nil
      return
    end

    @@groups.each_key do |groupName|
      groupCurrentTotalMilliAmps = 0
      @@configHash[groupName]['RPCMs'].each_value do |rpcm|
        apiAddress = rpcm['api_address']
        rpcm['outlets'].each_key do |outlet|
          groupCurrentTotalMilliAmps += milliampsFromCacheFor rpcm: apiAddress, outlet: outlet
        end
      end
      @@groups[groupName]['currentTotalAmps'] = groupCurrentTotalMilliAmps / 1000.0
      if currentTotalAmps(groupName: groupName) > limitAmps(groupName: groupName)
        if @@groups[groupName]['overTotalLimit'] == false
          @@groups[groupName]['overTotalLimit'] = true
          resetOverTotalLimitStabilized groupName: groupName
        else
          if (Time.now - @@groups[groupName]['overTotalLimitSince']) > delayBeforeTurnOffSeconds(groupName: groupName)
            @@groups[groupName]['overTotalLimitStabilized'] = true
          end
        end
      else
        @@groups[groupName]['overTotalLimit'] = false
        @@groups[groupName]['overTotalLimitStabilized'] = false
      end
      if (limitAmps(groupName: groupName) - currentTotalAmps(groupName: groupName)) > tryToTurnOnWhenAvailableAmps(groupName: groupName)
        if @@groups[groupName]['enoughAvailableAmps'] == false
          @@groups[groupName]['enoughAvailableAmps'] = true
          resetEnoughAvailableAmpsStabilized groupName: groupName
        else
          if (Time.now - @@groups[groupName]['enoughAvailableAmpsSince']) > delayBeforeTryToTurnOnSeconds(groupName: groupName)
            @@groups[groupName]['enoughAvailableAmpsStabilized'] = true
          end
        end
      else
        @@groups[groupName]['enoughAvailableAmps'] = false
        @@groups[groupName]['enoughAvailableAmpsStabilized'] = false
      end
    end
  end

  def self.resetOverTotalLimitStabilized groupName:
    @@groups[groupName]['overTotalLimitStabilized'] = false
    @@groups[groupName]['overTotalLimitSince'] = Time.now
  end

  def self.resetEnoughAvailableAmpsStabilized groupName:
    @@groups[groupName]['enoughAvailableAmpsStabilized'] = false
    @@groups[groupName]['enoughAvailableAmpsSince'] = Time.now
  end

  def self.printTotalsForGroups
    @@groups.each_key do |groupName|
      if @@verbose
        log text: "--------------------------"
        log text: "#{Time.now} [#{groupName}]"
        logPrint text: "(Limit Amps)/<Current Amps>/[Available Amps]: (#{limitAmps(groupName: groupName)})/"
        logPrint text: "<#{currentTotalAmps(groupName: groupName)}>/"
        log text: "[#{(limitAmps(groupName: groupName) - currentTotalAmps(groupName: groupName))}]"
        logPrint text: "Over Total Limit: #{@@groups[groupName]['overTotalLimit']}; "
        logPrint text: "Since: #{@@groups[groupName]['overTotalLimitSince']} (#{Time.now - @@groups[groupName]['overTotalLimitSince']} seconds); "
        logPrint text: "Stab Seconds: #{delayBeforeTurnOffSeconds(groupName: groupName)}; "
        log text: "Limit Stabilized: #{@@groups[groupName]['overTotalLimitStabilized']}"
        logPrint text: "Enough Available Amps: #{@@groups[groupName]['enoughAvailableAmps']}; "
        logPrint text: "Since: #{@@groups[groupName]['enoughAvailableAmpsSince']} (#{Time.now - @@groups[groupName]['enoughAvailableAmpsSince']} seconds); "
        logPrint text: "Stab Seconds: #{delayBeforeTryToTurnOnSeconds(groupName: groupName)}; "
        log text: "Available Amps Stabilized: #{@@groups[groupName]['enoughAvailableAmpsStabilized']}"
      end
    end
  end

  def self.findCandidatesToTurnOff groupName:
    candidates = []

    if not @@groups.has_key? groupName
      return nil
    end

    @@groups[groupName]['survivalPriorities'].keys.sort.reverse.each do |priority|
      currentPriorityOutlets = @@groups[groupName]['survivalPriorities'][priority]

      currentPriorityOutlets.each do |key, hash|
        apiAddress = hash['api_address']
        outletNumber = hash['outletNumber']
        adminState = adminStateFromCacheFor rpcm: apiAddress, outlet: outletNumber
        actualState = actualStateFromCacheFor rpcm: apiAddress, outlet: outletNumber
        circuitBreakerFiredState = circuitBreakerFiredStateFromCacheFor rpcm: apiAddress, outlet: outletNumber
        overcurrentTurnOffFiredState = overcurrentTurnOffFiredStateFromCacheFor rpcm: apiAddress, outlet: outletNumber

        if adminState == 'ON'
          if (actualState == 'ON') or (actualState == 'OFF' and circuitBreakerFiredState != 'ON' and overcurrentTurnOffFiredState != 'ON')
            candidates << hash
          end
        end
      end

      if candidates.size > 0
        return candidates
      end
    end

    return nil
  end

  def self.findCandidatesToTurnOn groupName:
    candidates = []

    if not @@groups.has_key? groupName
      return nil
    end

    @@groups[groupName]['survivalPriorities'].keys.sort.each do |priority|
      currentPriorityOutlets = @@groups[groupName]['survivalPriorities'][priority]

      currentPriorityOutlets.each do |key, hash|
        apiAddress = hash['api_address']
        outletNumber = hash['outletNumber']
        defaultState = hash['defaultState']
        adminState = adminStateFromCacheFor rpcm: apiAddress, outlet: outletNumber
        actualState = actualStateFromCacheFor rpcm: apiAddress, outlet: outletNumber

        if defaultState == 'on'
          if adminState == 'OFF' and actualState == 'OFF'
            candidates << hash
          end
        end
      end

      if candidates.size > 0
        return candidates
      end
    end

    return nil
  end

  def self.actOnCandidatesForChange
    changesApplied = false

    @@groups.each_key do |groupName|
      if @@groups[groupName]['overTotalLimitStabilized'] == true
        candidatesArray = findCandidatesToTurnOff groupName: groupName
        next if candidatesArray == nil

        candidatesArray.each do |candidateHash|
          apiAddress = candidateHash['api_address']
          outletNumber = candidateHash['outletNumber']
          comment = candidateHash['comment']

          log text: "Will TURN OFF #{groupName} #{outletNumber}@#{apiAddress} (#{comment})"
          if @@testMode == false
            RPCMAPIControl.switch apiAddress: apiAddress, outlet: outletNumber, state: 'off'
          end
        end
        resetOverTotalLimitStabilized groupName: groupName
        changesApplied = true
      elsif @@groups[groupName]['enoughAvailableAmpsStabilized'] == true
        candidatesArray = findCandidatesToTurnOn groupName: groupName
        next if candidatesArray == nil

        candidatesArray.each do |candidateHash|
          apiAddress = candidateHash['api_address']
          outletNumber = candidateHash['outletNumber']
          comment = candidateHash['comment']

          log text: "Will TURN ON #{groupName} #{outletNumber}@#{apiAddress} (#{comment})"
          if @@testMode == false
            RPCMAPIControl.switch apiAddress: apiAddress, outlet: outletNumber, state: 'on'
          end
        end
        resetEnoughAvailableAmpsStabilized groupName: groupName
        changesApplied = true
      end
    end

    if changesApplied == false
      log text: "no changes during this check" if @@verbose
    end
  end
end

class RPCMAPIControl
  def self.switch apiAddress:, outlet:, state:
    if (state != 'on') and (state != 'off')
      TotalCurrentControl.log text: "#{Time.now} wrong state requested #{state}"
      return
    end

    TotalCurrentControl.log text: "#{Time.now} Turning #{apiAddress} outlet #{outlet} #{state}"

    turnOffHttpRequest = EventMachine::HttpRequest.new("http://#{apiAddress}:8888/api/channel/#{outlet}/#{state}").put

    turnOffHttpRequest.errback do
      TotalCurrentControl.log text: "#{Time.now} failed to turn #{apiAddress} outlet #{outlet} #{state}"

      GC.start full_mark: true, immediate_sweep: true
    end

    turnOffHttpRequest.callback do
      TotalCurrentControl.log text: "#{Time.now} turned #{apiAddress} outlet #{outlet} #{state} successfully"

      GC.start full_mark: true, immediate_sweep: true
    end
  end

  def self.getCachedStatus apiAddress:, &block
    http = EventMachine::HttpRequest.new("http://#{apiAddress}:8888/api/cachedStatusWithFullNames").get

    http.errback do
      TotalCurrentControl.log text: "#{Time.now} Error requesting #{apiAddress}"

      GC.start full_mark: true, immediate_sweep: true
    end

    http.callback do
      jsonHash = JSON.parse http.response

      if jsonHash.class == Hash
        block.call jsonHash
      end

      GC.start full_mark: true, immediate_sweep: true
    end
  end
end

TotalCurrentControl.readConfig
TotalCurrentControl.log text: "#{Time.now}"
TotalCurrentControl.log text: 'RPCMs:'
TotalCurrentControl.log text: TotalCurrentControl.listOfDevices
TotalCurrentControl.log text: TotalCurrentControl.listOfSurvivalPriorities
if TotalCurrentControl.testMode == true
  TotalCurrentControl.log text: 'Running in test mode...'
end

if TotalCurrentControl.daemonize
  Process.daemon
end

EventMachine.run do
  TotalCurrentControl.setUpDeviceCacheRegularUpdate
  EventMachine.add_periodic_timer(2) do
    TotalCurrentControl.updateTotalsForGroups
    TotalCurrentControl.printTotalsForGroups
    TotalCurrentControl.actOnCandidatesForChange
    GC.start full_mark: true, immediate_sweep: true
  end
end
