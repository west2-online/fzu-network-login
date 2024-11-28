# -*- coding: utf-8 -*-

import requests
import json
import time
from urllib.parse import urlparse, parse_qs, quote
import argparse
import yaml
import os

user_agent = ''
username = ''
password = ''
max_retries = 3 # 超时重试次数

def read_config(config_path):
    if os.path.exists(config_path):
        with open(config_path, 'r') as stream:
            try:
                config = yaml.safe_load(stream)
                return config
            except yaml.YAMLError as exc:
                print(exc)
                return None
    else:
        return None

def parse_arguments():
    global username, password, user_agent # 使用全局变量
    default_username = ''
    default_password = ''
    default_user_agent = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36 Edg/131.0.0.0'

    # 先尝试读取配置文件
    config = read_config('config.yaml')
    if config:
        default_username = config.get('username', '')
        default_password = config.get('password', '')
        default_user_agent = config.get('user_agent', '')

    # 如果传入参数则使用传入参数
    parser = argparse.ArgumentParser(description='Login script with user credentials')
    parser.add_argument('-u', '--username', default=default_username, help='Username for login')
    parser.add_argument('-p', '--password', default=default_password, help='Password for login')
    parser.add_argument('-a', '--user-agent', default=default_user_agent, help='User agent for requests')
    args = parser.parse_args()
    username = args.username
    password = args.password
    user_agent = args.user_agent

def parse_response_json(response):
    try:
        # 尝试使用 UTF-8 解码
        content = response.content.decode('utf-8')
    except UnicodeDecodeError:
        try:
            # 如果 UTF-8 失败，尝试使用 GBK 解码
            content = response.content.decode('gbk')
        except UnicodeDecodeError:
            return None, "Response cannot be decoded."

    try:
        response_json = json.loads(content)
        return response_json, None
    except json.JSONDecodeError:
        return None, "Response is not valid JSON."

def logout(userindex):
    logout_url = 'http://59.77.227.227/eportal/InterFace.do?method=logout'
    headers = {
        'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8',
        'User-Agent': user_agent,
        'Connection': 'keep-alive',
        'Accept': '*/*',
        'Origin': 'http://59.77.227.227',
        'DNT': '1',
        'Accept-Encoding': 'gzip, deflate',
        'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8,en-GB;q=0.7,en-US;q=0.6',
    }
    data = {
        'userIndex': userindex
    }
    response = requests.post(logout_url, headers=headers, data=data)
    response_json, error = parse_response_json(response)

    if error:
        print(f"Logout device fail, parse JSON meet error: {error}")
        return False

    if response_json.get('result') == 'success':
        print("Logout device successful.")
        return True
    else:
        print(f"Logout device failed, msg: {response_json.get('message', 'Unknown error occurred.')}")
        return False

# fail = 获取用户信息失败，用户可能已经下线
# wait = 用户信息不完整，请稍后重试
# success = 获取用户信息成功
# error = 遇到错误
def check_online():
    url = 'http://59.77.227.227/eportal/InterFace.do?method=getOnlineUserInfo'
    cookies = {}
    data = {'userIndex': ''}
    response = requests.post(url, headers={'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8'}, cookies=cookies, data=data)

    response_json, error = parse_response_json(response)

    if error:
        print(f"Parse JSON meet error: {error}")
        print(f"Response content: {response.content.decode('utf-8')}")
        return "error", None

    result = response_json.get('result', 'fail')
    userindex = response_json.get('userIndex', None) # 获取设备 id，虽然不知道为什么它这里写的是 userIndex
    message = response_json.get('message', 'Unknown error occurred.') # 状态消息
    username = response_json.get('userName', '未知') # 用户名， e.g. 052106112
    userid = response_json.get('userId', '未知') # 用户id， e.g. 052106112
    userip = response_json.get('userIp', '未知') # 用户IP， e.g. 10.132.50.80
    usermac = response_json.get('userMac', '未知') # 用户MAC，e.g. 5ce35ef1b708

    # 美化打印输出
    print(f"Status Message: {message}")
    print(f"Username: {username}")
    print(f"User ID: {userid}")
    print(f"User IP: {userip}")
    print(f"USer MAC: {usermac}")
    print(f"Device ID: {userindex}\n")

    return result, userindex

# 获取 Page 信息，与登录无关，但需要登一次
def post_page_info(referer_url, encoded_query_string, cookies):
    page_info_url = 'http://59.77.227.227/eportal/InterFace.do?method=pageInfo'
    headers = {
        'Host': '59.77.227.227',
        'Connection': 'keep-alive',
        'User-Agent': user_agent,
        'DNT': '1',
        'Accept': '*/*',
        'Origin': 'http://59.77.227.227',
        'Referer': referer_url,
        'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8,en-GB;q=0.7,en-US;q=0.6',
        'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8',
    }
    data = {'queryString': encoded_query_string}
    requests.post(page_info_url, headers=headers, cookies=cookies, data=data)

# 登录函数，返回成功或失败
def login(username, password):
    # 获取重定向URL
    response = requests.get('http://123.123.123.123')
    redirect_url = response.text.split("location.href='")[1].split("'")[0]

    # 访问 redirect_url 以获取 cookies，格式类似于 {'JSESSIONID': 'A56BE9EB52B0F6E02A5122C3B3BD5A28'}
    redirect_response = requests.get(redirect_url)
    cookies = redirect_response.cookies

    # 解析URL
    parsed_url = urlparse(redirect_url)
    query_params = parse_qs(parsed_url.query)
    query_string = "&".join(["{}={}".format(k, v[0]) for k, v in query_params.items()])
    encoded_query_string = quote(query_string, safe='')

    # 模拟普通用户获取 page
    post_page_info(redirect_url, encoded_query_string, cookies)

    # 执行登录
    login_url = 'http://59.77.227.227/eportal/InterFace.do?method=login'
    headers = {
        'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8',
        'Referer': redirect_url,
        'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8,en-GB;q=0.7,en-US;q=0.6',
        'Accept-Encoding': 'gzip, deflate',
        'Origin': 'http://59.77.227.227',
        'DNT': '1',
        'Accept': '*/*',
        'User-Agent': user_agent,
        'Connection': 'keep-alive',
        'Host': '59.77.227.227',
    }
    data = {
        'userId': username,
        'password': password,
        'queryString': encoded_query_string,
        'passwordEncrypt': 'false',
        'validcode': '',
        'operatorUserId': '',
        'operatorPwd': '',
        'service': '',
    }
    login_response = requests.post(login_url, headers=headers, cookies=cookies, data=data)

    response_json, error = parse_response_json(login_response)
    if error:
        print(f"Error: {error}")
        print(f"Response content: {login_response.content.decode('utf-8')}")
        return False

    if response_json.get('result') == "success":
        print("Login successful.")
        return True
    else:
        message = response_json.get('message', 'Unknown error occurred.')
        print(f"Login failed. Message: {message}")
        return False
    # 可能输出：设备未注册,请在ePortal上添加认证设备
    # 可能输出：运营商用户认证失败!失败原因[RADIUS-0036:Duplicate dialing time is too short]


# 检查在线状态，如果不在线则尝试登录，登录返回 success 后会再次检查在线状态
# 如果持续为 wait 状态超过 3 次，则尝试登出，登出成功后再次尝试登录
def main():
    parse_arguments()

    retries = 0  # 当前重试次数
    while retries < max_retries:
        res, userindex = check_online()  # 获取在线状态和userindex
        if res == "success": # 在线，则退出
            print("Already online. No need to login.")
            break
        elif res == "wait":
            print("Waiting for online status...")
            retries += 1
            if retries >= max_retries:
                print("Reached maximum retries, proceeding to logout.")
                if logout(userindex):  # 如果登出成功
                    print("Logged out successfully. Proceeding to login.")
                    if login(username, password):  # 尝试重新登录
                        print("Login successful. Checking online status again.")
                        retries = 0  # 重置重试次数
                    else:
                        # 重新登录失败，此时我们无法确定是网络问题还是密码错误，因此直接退出
                        print("Login failed. Please check your credentials or network status.")
                        break
                else:
                    print("Logout failed. Please check the network or userindex validity.")
                    break
            time.sleep(5)  # 等待5秒钟再次检查
        elif res == "fail":
            print("Currently offline. Proceeding to login.")
            if login(username, password):  # 登录
                print("Login successful. Checking online status again.")
                retries = 0  # 重置重试次数
            else:
                # 登录失败，由于是第一次登录，基本可以确定是密码错误
                print("Login failed. Please check your credentials or network status.")
                break
        elif res == "error":
            print("Error occurred. Please check the error message above.")
            break
        else:
            print("Unexpected status received.")
            break

if __name__ == '__main__':
    main()
