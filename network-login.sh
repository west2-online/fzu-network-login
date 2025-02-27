#!/bin/bash

# 配置变量
user_agent=''
username=''
password=''
max_retries=3 # 超时重试次数
config_file='config.yaml'

# 检查依赖
check_dependencies() {
    local dependencies=("jq" "yq" "sed" "curl" "awk")
    for dep in "${dependencies[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            echo "Error: $dep is not installed."
            return 1
        fi
    done
    return 0
}

# 读取配置文件
read_config() {
    if [[ -f "$config_file" ]]; then
        username=$(yq -r '.username' "$config_file")
        password=$(yq -r '.password' "$config_file")
        user_agent=$(yq -r '.user_agent' "$config_file")
    fi
}

# 解析 JSON 响应
parse_response_json() {
    # 使用 jq 解析 JSON
    if ! err=$(echo "$1" | jq . 2>&1 > /dev/null); then
        echo "Error parsing JSON: $err"
        return 1
    fi
}

# 登出
logout() {
    local userindex=$1
    local logout_url='http://172.16.0.46/eportal/InterFace.do?method=logout'
    local response=$(curl -s -X POST -H "Content-Type: application/x-www-form-urlencoded; charset=UTF-8" \
        -H "User-Agent: $user_agent" \
        -H "Connection: keep-alive" \
        -H "Accept: */*" \
        -H "Origin: http://172.16.0.46" \
        -H "DNT: 1" \
        -H "Accept-Encoding: gzip, deflate" \
        -H "Accept-Language: zh-CN,zh;q=0.9,en;q=0.8,en-GB;q=0.7,en-US;q=0.6" \
        --data-urlencode "userIndex=$userindex" \
        "$logout_url")

    if parse_response_json "$response"; then
        local result=$(echo "$response" | jq -r '.result')
        if [[ "$result" == "success" ]]; then
            echo "Logout device successful."
            return 0
        else
            local message=$(echo "$response" | jq -r '.message')
            echo "Logout device failed, msg: $message"
            return 1
        fi
    else
        echo "Logout device fail, parse JSON meet error"
        return 1
    fi
}

# 检查在线状态
check_online() {
    local url='http://172.16.0.46/eportal/InterFace.do?method=getOnlineUserInfo'
    local response=$(curl -s -X POST -H "Content-Type: application/x-www-form-urlencoded; charset=UTF-8" \
        --data-urlencode "userIndex=" \
        "$url")

    if parse_response_json "$response"; then
        local result=$(echo "$response" | jq -r '.result')
        userindex=$(echo "$response" | jq -r '.userIndex') # 需要设置为全局变量
        local message=$(echo "$response" | jq -r '.message')
        local username=$(echo "$response" | jq -r '.userName')
        local userid=$(echo "$response" | jq -r '.userId')
        local userip=$(echo "$response" | jq -r '.userIp')
        local usermac=$(echo "$response" | jq -r '.userMac')

        echo "Status Message: $message"
        echo "Username: $username"
        echo "User ID: $userid"
        echo "User IP: $userip"
        echo "User MAC: $usermac"
        echo "Device ID: $userindex"

        if [[ "$result" == "success" ]]; then
            return 0
        elif [[ "$result" == "fail" ]]; then
            return 1
        elif [[ "$result" == "wait" ]]; then
            return 2
        fi
    else
        echo "Error occurred. Please check the error message above."
        return 3
    fi
}

# 获取page信息，与登录无关，但需要尝试访问一次
get_page_info() {
    local referer_url=$1
    local encoded_query_string=$2
    local JSESSIONID=$3

    local url='http://172.16.0.46/eportal/InterFace.do?method=pageInfo'
    local response=$(curl -s -X POST \
        -H "Host: 172.16.0.46" \
        -H "Connection: keep-alive" \
        -H "User-Agent: $user_agent" \
        -H "DNT: 1" \
        -H "Accept: */*" \
        -H "Origin: http://172.16.0.46" \
        -H "Referer: $referer_url" \
        -H "Accept-Language: zh-CN,zh;q=0.9,en;q=0.8,en-GB;q=0.7,en-US;q=0.6" \
        -H "Content-Type: application/x-www-form-urlencoded; charset=UTF-8" \
        --cookie "JSESSIONID=$JSESSIONID" \
        --data-urlencode "queryString=$encoded_query_string" \
        "$url")
}

# 登录
login() {
    # 发送请求并获取页面内容
    page_content=$(curl -s 'http://123.123.123.123')

    # 从页面内容中提取重定向 URL
    redirect_url=$(echo "$page_content" | sed -n "s/.*location.href='\([^']*\).*/\1/p")

    # 使用重定向 URL 发送请求，获取cookies，并将cookies保存到cookies.txt文件中
    curl -s -c cookies.txt "$redirect_url" -o /dev/null

    # 从cookies.txt中提取JSESSIONID的值
    JSESSIONID=$(awk '/JSESSIONID/ {print $7}' cookies.txt)

    # 解析重定向 URL 以获取查询字符串
    query_string=$(echo "$redirect_url" | sed -n 's/.*\?\(.*\)/\1/p')

    # 使用jq对查询字符串进行URL编码
    encoded_query_string=$(echo "$query_string" | jq -sRr @uri)

    get_page_info $redirect_url $encoded_query_string $JSESSIONID

    local login_url='http://172.16.0.46/eportal/InterFace.do?method=login'
    local response=$(curl -s -X POST -H "Content-Type: application/x-www-form-urlencoded; charset=UTF-8" \
        -H "Referer: $redirect_url" \
        -H "Accept-Language: zh-CN,zh;q=0.9,en;q=0.8,en-GB;q=0.7,en-US;q=0.6" \
        -H "Accept-Encoding: gzip, deflate" \
        -H "Origin: http://172.16.0.46" \
        -H "DNT: 1" \
        -H "Accept: */*" \
        -H "User-Agent: $user_agent" \
        -H "Connection: keep-alive" \
        -H "Host: 172.16.0.46" \
        --data-urlencode "userId=$username" \
        --data-urlencode "password=$password" \
        --data-urlencode "queryString=$encoded_query_string" \
        --data-urlencode "passwordEncrypt=false" \
        --data-urlencode "validcode=" \
        --data-urlencode "operatorUserId=" \
        --data-urlencode "operatorPwd=" \
        --data-urlencode "service=" \
        --cookie "JSESSIONID=$JSESSIONID" \
        "$login_url")

    if parse_response_json "$response"; then
        local result=$(echo "$response" | jq -r '.result')
        if [[ "$result" == "success" ]]; then
            echo "Login successful."
            return 0
        else
            local message=$(echo "$response" | jq -r '.message')
            echo "Login failed. Message: $message"
            return 1
        fi
    else
        echo "Login failed. Response is not valid JSON."
        return 1
    fi
}

# 主函数
main() {
    check_dependencies
    if [[ $? -ne 0 ]]; then
        echo "Dependencies check failed. Exiting."
        exit 1
    fi
    # 读取配置文件
    read_config

    retries=0
    while [[ $retries -lt $max_retries ]]; do
        check_online
        status=$? # 获取check_online的状态，其中userindex会以全局变量形式展示，可以直接`echo $userindex`

        if [[ $status -eq 0 ]]; then
            echo "Already online. No need to login."
            break
        elif [[ $status -eq 1 ]]; then
            echo "Currently offline. Proceeding to login."
            if login; then
                echo "Login successful. Checking online status again."
                retries=0 # 重置重试次数
            else
                echo "Login failed. Please check your credentials or network status."
                break
            fi
        elif [[ $status -eq 2 ]]; then
            echo "Waiting for online status..."
            ((retries++))
            if [[ $retries -ge $max_retries ]]; then
                echo "Reached maximum retries, proceeding to logout."
                if logout "$userindex"; then
                    echo "Logged out successfully. Proceeding to login."
                    if login; then
                        echo "Login successful. Checking online status again."
                        retries=0 # 重置重试次数
                    else
                        echo "Login failed. Please check your credentials or network status."
                        break
                    fi
                else
                    echo "Logout failed. Please check the network or userindex validity."
                    break
                fi
            fi
            sleep 5 # 等待5秒钟再次检查
        elif [[ $status -eq 3 ]]; then
            echo "Error occurred. Please check the error message above."
            break
        else
            echo "Unexpected status received."
            break
        fi
    done
}

main "$@"



