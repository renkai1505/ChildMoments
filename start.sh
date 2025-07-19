#!/bin/bash

# Moments 一键启动脚本
# 支持开发模式 (已移除Docker模式)

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 打印带颜色的消息
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 检查命令是否存在
check_command() {
    if ! command -v "$1" >/dev/null 2>&1; then
        print_error "$1 未安装，请先安装 $1"
        exit 1
    fi
}

# 检查端口是否被占用
check_port() {
    local port=$1
    if command -v lsof >/dev/null 2>&1; then
        if lsof -Pi :$port -sTCP:LISTEN -t >/dev/null 2>&1; then
            print_warning "端口 $port 已被占用"
            return 1
        fi
    elif command -v ss >/dev/null 2>&1; then
        if ss -tuln | grep -q ":$port "; then
            print_warning "端口 $port 已被占用"
            return 1
        fi
    elif command -v netstat >/dev/null 2>&1; then
        if netstat -tuln | grep -q ":$port "; then
            print_warning "端口 $port 已被占用"
            return 1
        fi
    else
        print_warning "无法检查端口状态，缺少 lsof/ss/netstat 工具"
    fi
    return 0
}

# 检查目录结构
check_directories() {
    if [ ! -d "front" ]; then
        print_error "front 目录不存在，请确保在项目根目录运行此脚本"
        exit 1
    fi
    
    if [ ! -d "backend" ]; then
        print_error "backend 目录不存在，请确保在项目根目录运行此脚本"
        exit 1
    fi
}

# 安全地杀死进程（包括子进程）
safe_kill() {
    local pid=$1
    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
        print_info "正在停止进程树 (主PID: $pid)..."
        
        # 首先尝试优雅地停止进程组
        if kill -TERM -"$pid" 2>/dev/null; then
            print_info "发送TERM信号到进程组 $pid"
        else
            # 如果进程组不存在，尝试杀死单个进程
            kill -TERM "$pid" 2>/dev/null || true
        fi
        
        # 等待进程结束，最多等待8秒
        local count=0
        while kill -0 "$pid" 2>/dev/null && [ $count -lt 80 ]; do
            sleep 0.1
            count=$((count + 1))
        done
        
        # 如果进程仍在运行，强制杀死整个进程树
        if kill -0 "$pid" 2>/dev/null; then
            print_warning "进程未响应TERM信号，强制结束进程树 $pid"
            
            # 强制杀死进程组
            kill -KILL -"$pid" 2>/dev/null || true
            # 强制杀死主进程
            kill -KILL "$pid" 2>/dev/null || true
            
            # 额外的清理：查找并杀死相关的子进程
            cleanup_related_processes "$pid"
        fi
        return 0
    fi
    return 1
}

# 清理相关进程（Go和Node.js的子进程）
cleanup_related_processes() {
    local main_pid=$1
    
    # 清理Go相关进程
    print_info "清理Go相关进程..."
    pkill -f "go-build.*moments" 2>/dev/null || true
    pkill -f "moments.*backend" 2>/dev/null || true
    
    # 清理Node.js/pnpm相关进程  
    print_info "清理Node.js相关进程..."
    pkill -f "nuxt dev" 2>/dev/null || true
    pkill -f "pnpm.*dev" 2>/dev/null || true
    pkill -f "node.*moments" 2>/dev/null || true
    pkill -f ".pnpm.*moments" 2>/dev/null || true
    
    # 等待进程清理完成
    sleep 1
}

# 强制清理所有相关进程
force_cleanup_all() {
    print_warning "执行强制清理所有Moments相关进程..."
    
    # 根据进程名和路径特征清理
    local current_dir=$(basename "$(pwd)")
    
    # 清理Go进程
    pkill -9 -f "go run.*backend" 2>/dev/null || true
    pkill -9 -f "go-build.*moments" 2>/dev/null || true
    pkill -9 -f "$current_dir.*backend" 2>/dev/null || true
    
    # 清理Node.js进程
    pkill -9 -f "nuxt dev" 2>/dev/null || true
    pkill -9 -f "pnpm.*dev.*$current_dir" 2>/dev/null || true
    pkill -9 -f "node.*$current_dir.*front" 2>/dev/null || true
    pkill -9 -f "vite.*$current_dir" 2>/dev/null || true
    
    # 清理端口占用
    if command -v fuser >/dev/null 2>&1; then
        print_info "清理端口占用..."
        fuser -k 3000/tcp 2>/dev/null || true
        fuser -k 37892/tcp 2>/dev/null || true
    fi
    
    print_success "强制清理完成"
}

# 显示帮助信息
show_help() {
    echo "Moments 一键启动脚本"
    echo ""
    echo "用法: $0 [选项]"
    echo ""
    echo "选项:"
    echo "  dev         启动开发模式 (前端 + 后端) [默认]"
    echo "  frontend    仅启动前端开发服务器"
    echo "  backend     仅启动后端开发服务器"
    echo "  stop        停止所有服务"
    echo "  force-stop  强制停止所有相关进程"
    echo "  clean       清理构建文件和依赖"
    echo "  status      查看服务状态"
    echo "  logs        查看服务日志"
    echo "  help        显示此帮助信息"
    echo ""
    echo "示例:"
    echo "  $0 dev         # 启动开发模式"
    echo "  $0 frontend    # 仅启动前端"
    echo "  $0 backend     # 仅启动后端"
    echo "  $0 stop        # 停止所有服务"
    echo "  $0 force-stop  # 强制停止所有相关进程（包括子进程）"
    echo "  $0 status      # 查看服务状态"
    echo "  $0 logs        # 查看最新日志"
}

# 启动开发模式
start_dev() {
    print_info "启动开发模式..."
    
    # 检查目录结构
    check_directories
    
    # 检查依赖
    check_command "node"
    check_command "pnpm"
    check_command "go"
    
    # 检查端口
    if ! check_port 3000; then
        read -p "前端端口 3000 被占用，是否继续？(y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_error "启动取消"
            exit 1
        fi
    fi
    
    if ! check_port 37892; then
        read -p "后端端口 37892 被占用，是否继续？(y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_error "启动取消"
            exit 1
        fi
    fi
    
    # 先停止可能存在的服务
    stop_services_quiet
    
    # 安装依赖
    print_info "检查并安装前端依赖..."
    cd front || exit 1
    if [ ! -d "node_modules" ] || [ ! -f "pnpm-lock.yaml" ]; then
        print_info "安装前端依赖..."
        pnpm install
    else
        print_info "前端依赖已存在，跳过安装"
    fi
    cd .. || exit 1
    
    print_info "检查后端依赖..."
    cd backend || exit 1
    if [ ! -f "go.sum" ]; then
        print_info "下载后端依赖..."
        go mod download
    else
        print_info "后端依赖已存在，跳过下载"
    fi
    cd .. || exit 1
    
    # 启动后端
    print_info "启动后端服务器 (端口: 37892)..."
    cd backend || exit 1
    # 使用setsid创建新的会话，便于后续清理整个进程组
    nohup setsid go run . > ../backend.log 2>&1 &
    BACKEND_PID=$!
    echo $BACKEND_PID > ../backend.pid
    cd .. || exit 1
    
    # 验证后端启动
    print_info "等待后端启动..."
    local count=0
    while [ $count -lt 30 ]; do
        if kill -0 $BACKEND_PID 2>/dev/null; then
            if command -v curl >/dev/null 2>&1; then
                if curl -s http://localhost:37892 >/dev/null 2>&1; then
                    break
                fi
            else
                # 如果没有curl，等待更长时间
                if [ $count -gt 10 ]; then
                    break
                fi
            fi
        else
            print_error "后端启动失败，请查看 backend.log"
            cat backend.log
            exit 1
        fi
        sleep 1
        count=$((count + 1))
    done
    
    if [ $count -eq 30 ]; then
        print_warning "后端可能启动较慢，继续启动前端..."
    else
        print_success "后端启动成功"
    fi
    
    # 启动前端
    print_info "启动前端开发服务器 (端口: 3000)..."
    cd front || exit 1
    # 使用setsid创建新的会话，便于后续清理整个进程组
    nohup setsid pnpm run dev > ../frontend.log 2>&1 &
    FRONTEND_PID=$!
    echo $FRONTEND_PID > ../frontend.pid
    cd .. || exit 1
    
    # 验证前端启动
    print_info "等待前端启动..."
    sleep 5
    if ! kill -0 $FRONTEND_PID 2>/dev/null; then
        print_error "前端启动失败，请查看 frontend.log"
        tail -n 20 frontend.log
        exit 1
    fi
    
    print_success "开发模式启动完成!"
    echo ""
    print_info "服务信息:"
    print_info "  前端地址: http://localhost:3000"
    print_info "  后端地址: http://localhost:37892"
    print_info "  API文档: http://localhost:37892/swagger/"
    echo ""
    print_info "管理命令:"
    print_info "  查看状态: $0 status"
    print_info "  查看日志: $0 logs"
    print_info "  停止服务: $0 stop"
    echo ""
    print_info "日志文件: frontend.log, backend.log"
}

# 仅启动前端
start_frontend() {
    print_info "启动前端开发服务器..."
    
    check_directories
    check_command "node"
    check_command "pnpm"
    
    if ! check_port 3000; then
        read -p "端口 3000 被占用，是否继续？(y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_error "启动取消"
            exit 1
        fi
    fi
    
    cd front || exit 1
    if [ ! -d "node_modules" ]; then
        print_info "安装依赖..."
        pnpm install
    fi
    
    print_info "启动中..."
    pnpm run dev
}

# 仅启动后端
start_backend() {
    print_info "启动后端开发服务器..."
    
    check_directories
    check_command "go"
    
    if ! check_port 37892; then
        read -p "端口 37892 被占用，是否继续？(y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_error "启动取消"
            exit 1
        fi
    fi
    
    cd backend || exit 1
    if [ ! -f "go.sum" ]; then
        print_info "下载依赖..."
        go mod download
    fi
    
    print_info "启动中..."
    go run .
}

# 静默停止服务（不输出信息）
stop_services_quiet() {
    # 停止后端
    if [ -f backend.pid ]; then
        BACKEND_PID=$(cat backend.pid 2>/dev/null)
        safe_kill "$BACKEND_PID" >/dev/null 2>&1
        rm -f backend.pid
    fi
    
    # 停止前端
    if [ -f frontend.pid ]; then
        FRONTEND_PID=$(cat frontend.pid 2>/dev/null)
        safe_kill "$FRONTEND_PID" >/dev/null 2>&1
        rm -f frontend.pid
    fi
}

# 停止所有服务
stop_services() {
    print_info "停止所有服务..."
    
    local stopped=false
    
    # 停止后端
    if [ -f backend.pid ]; then
        BACKEND_PID=$(cat backend.pid 2>/dev/null)
        if safe_kill "$BACKEND_PID"; then
            print_success "已停止后端服务 (PID: $BACKEND_PID)"
            stopped=true
        fi
        rm -f backend.pid
    fi
    
    # 停止前端
    if [ -f frontend.pid ]; then
        FRONTEND_PID=$(cat frontend.pid 2>/dev/null)
        if safe_kill "$FRONTEND_PID"; then
            print_success "已停止前端服务 (PID: $FRONTEND_PID)"
            stopped=true
        fi
        rm -f frontend.pid
    fi
    
    if [ "$stopped" = true ]; then
        print_success "所有服务已停止"
    else
        print_info "没有找到运行中的服务"
    fi
}

# 查看服务状态
show_status() {
    print_info "服务状态:"
    echo ""
    
    local frontend_running=false
    local backend_running=false
    
    # 检查前端状态
    if [ -f frontend.pid ]; then
        FRONTEND_PID=$(cat frontend.pid 2>/dev/null)
        if [ -n "$FRONTEND_PID" ] && kill -0 "$FRONTEND_PID" 2>/dev/null; then
            print_success "前端服务: 运行中 (PID: $FRONTEND_PID, 端口: 3000)"
            frontend_running=true
        else
            print_error "前端服务: 已停止 (PID文件存在但进程不存在)"
            rm -f frontend.pid
        fi
    else
        print_warning "前端服务: 未启动"
    fi
    
    # 检查后端状态
    if [ -f backend.pid ]; then
        BACKEND_PID=$(cat backend.pid 2>/dev/null)
        if [ -n "$BACKEND_PID" ] && kill -0 "$BACKEND_PID" 2>/dev/null; then
            print_success "后端服务: 运行中 (PID: $BACKEND_PID, 端口: 37892)"
            backend_running=true
        else
            print_error "后端服务: 已停止 (PID文件存在但进程不存在)"
            rm -f backend.pid
        fi
    else
        print_warning "后端服务: 未启动"
    fi
    
    echo ""
    if [ "$frontend_running" = true ] && [ "$backend_running" = true ]; then
        print_info "访问地址:"
        print_info "  应用首页: http://localhost:3000"
        print_info "  API接口: http://localhost:37892"
        print_info "  API文档: http://localhost:37892/swagger/"
    elif [ "$frontend_running" = true ]; then
        print_info "仅前端运行: http://localhost:3000"
    elif [ "$backend_running" = true ]; then
        print_info "仅后端运行: http://localhost:37892"
    fi
}

# 查看日志
show_logs() {
    print_info "最新日志内容:"
    echo ""
    
    if [ -f backend.log ]; then
        print_info "=== 后端日志 (最新20行) ==="
        tail -n 20 backend.log
        echo ""
    fi
    
    if [ -f frontend.log ]; then
        print_info "=== 前端日志 (最新20行) ==="
        tail -n 20 frontend.log
        echo ""
    fi
    
    if [ ! -f backend.log ] && [ ! -f frontend.log ]; then
        print_warning "没有找到日志文件"
    fi
}

# 清理构建文件
clean_build() {
    print_info "清理构建文件和依赖..."
    
    # 先停止服务
    stop_services_quiet
    
    # 清理前端
    if [ -d "front" ]; then
        print_info "清理前端文件..."
        cd front || exit 1
        rm -rf .output dist node_modules .nuxt
        cd .. || exit 1
    fi
    
    # 清理后端
    if [ -d "backend" ]; then
        print_info "清理后端文件..."
        cd backend || exit 1
        rm -rf dist public
        go clean -cache -modcache -testcache 2>/dev/null || true
        cd .. || exit 1
    fi
    
    # 删除日志和PID文件
    rm -f frontend.log backend.log frontend.pid backend.pid
    
    print_success "清理完成"
}

# 主函数
main() {
    case "${1:-dev}" in
        "dev")
            start_dev
            ;;
        "frontend")
            start_frontend
            ;;
        "backend")
            start_backend
            ;;
        "stop")
            stop_services
            ;;
        "force-stop")
            stop_services
            force_cleanup_all
            ;;
        "clean")
            clean_build
            ;;
        "status")
            show_status
            ;;
        "logs")
            show_logs
            ;;
        "help"|"-h"|"--help")
            show_help
            ;;
        *)
            print_error "未知选项: $1"
            echo ""
            show_help
            exit 1
            ;;
    esac
}

# 捕获中断信号，优雅退出
cleanup() {
    echo ""
    print_info "接收到中断信号，正在停止服务..."
    stop_services_quiet
    print_info "清理完成，退出"
    exit 0
}

trap cleanup INT TERM

# 运行主函数
main "$@"
