*** Settings ***

Library         OperatingSystem

Suite Setup     Prepare

*** Keywords ***

Prepare
    ${NGINX_IP}                     Get Environment Variable        NGINX_SERVICE_HOST   127.0.0.1
    Set Global Variable             ${NGINX_IP}                     ${NGINX_IP}

*** Test Cases ***

test
    ${CODE}    ${OUTPUT} =          Run and Return RC and Output    curl -v --connect-timeout 3 http://${NGINX_IP}
    Log                             ${OUTPUT}
    Should Be Equal As Integers     ${CODE}                         0
    Should Contain                  ${OUTPUT}                       Welcome to nginx!