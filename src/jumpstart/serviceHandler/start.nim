import parsecfg
import os, osproc
import std/threadpool
import status
import ../logging
include ../commonImports
import globalVariables

proc startService*(serviceName: string) =
    ## Start an service.
    var service: Config

    # Load the configuration
    try:
        if dirExists("/run/serviceHandler/"&serviceName):
            warn "Service "&serviceName&" is already running, not starting it again"
            return

        createDir("/run/serviceHandler/"&serviceName)
        service = loadConfig(servicePath&"/"&serviceName)
    except CatchableError:
        warn "Service "&serviceName&" couldn't be started, possibly broken configuration?"
        return
    
    
    #var workDir: string
    #try:
    #    workDir = service.getSectionValue("Settings", "workDir")
    #except CatchableError:
    #    workDir = "/"

    createDir("/run/serviceHandler/"&serviceName)
    let process = startProcess(command = service.getSectionValue("Service",
            "exec"), options = {poEvalCommand, poUsePath, poDaemon})

    services = services&(serviceName: serviceName, process: process)

    spawn statusDaemon(process, serviceName)
    ok "Started "&serviceName
