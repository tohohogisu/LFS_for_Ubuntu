#!/bin/bash
# LichtFeld-Studio Ubuntu 22.04 + GCC14 + CUDA12.8
# 完全自動ビルド＆再配布ZIP統合スクリプト
# 2026/03/23 SDL3 依存追加版

set -e

echo "=== 🌈 LichtFeld-Studio 自動ビルド＋lib同梱ZIP作成 開始 ==="

# --- 事前sudo認証（最初の一度だけパスワード入力）---
sudo -v
while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &

# --- ディレクトリ準備 ---
cd ~
mkdir -p repos
cd repos

# --- CUDA 12.8 インストール ---
echo "🔧 CUDA 12.8 セットアップ中..."

# apt pin ファイルを取得して優先度設定
wget https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/x86_64/cuda-ubuntu2204.pin
sudo mv cuda-ubuntu2204.pin /etc/apt/preferences.d/cuda-repository-pin-600

# ローカル CUDA リポジトリ .deb を取得して登録
wget https://developer.download.nvidia.com/compute/cuda/12.8.0/local_installers/cuda-repo-ubuntu2204-12-8-local_12.8.0-570.86.10-1_amd64.deb
sudo dpkg -i cuda-repo-ubuntu2204-12-8-local_12.8.0-570.86.10-1_amd64.deb
sudo cp /var/cuda-repo-ubuntu2204-12-8-local/cuda-*-keyring.gpg /usr/share/keyrings/

# CUDA 12.8 ToolKit をインストール
sudo apt update -y && sudo apt -y install cuda-toolkit-12-8

# --- PATH設定（永続化＋即時反映） ---
if ! grep -q "cuda-12.8" ~/.bashrc; then
  echo 'export PATH=/usr/local/cuda-12.8/bin${PATH:+:${PATH}}' >> ~/.bashrc
  echo 'export LD_LIBRARY_PATH=/usr/local/cuda-12.8/lib64${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}' >> ~/.bashrc
fi
source ~/.bashrc
export PATH=/usr/local/cuda-12.8/bin:$PATH
export CUDACXX=/usr/local/cuda-12.8/bin/nvcc

# --- 必須ツール（ビルドツール + SDL3 GUI 依存）---
sudo apt update && sudo apt install -y \
  build-essential flex bison libgmp3-dev libmpc-dev libmpfr-dev libisl-dev texinfo \
  git ninja-build pkg-config curl zip unzip nasm \
  libx11-dev libxft-dev libxext-dev \
  libxrandr-dev libxinerama-dev libxcursor-dev libxi-dev \
  libgl1-mesa-dev libglu1-mesa-dev libegl1-mesa-dev \
  libwayland-dev libxkbcommon-dev libibus-1.0-dev \
  autoconf autoconf-archive automake libtool m4 gettext libffi-dev libssl-dev

# --- GCC 14.3.0 ---
echo "⚙️ GCC 14.3.0 ビルド中（時間かかります）..."

sudo fallocate -l 16G /swapfile || true
sudo chmod 600 /swapfile || true
sudo mkswap /swapfile || true
sudo swapon /swapfile || true
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab >/dev/null

curl -fLO https://ftp.gnu.org/gnu/gcc/gcc-14.3.0/gcc-14.3.0.tar.xz
tar -xf gcc-14.3.0.tar.xz
cd gcc-14.3.0
./contrib/download_prerequisites
mkdir build && cd build
../configure --prefix=/usr/local/gcc-14 --disable-multilib --enable-languages=c,c++
make -j"$(nproc)"
sudo make install
cd ~/repos

sudo update-alternatives --install /usr/bin/gcc gcc /usr/local/gcc-14/bin/gcc 140
sudo update-alternatives --install /usr/bin/g++ g++ /usr/local/gcc-14/bin/g++ 140
sudo update-alternatives --set gcc /usr/local/gcc-14/bin/gcc
sudo update-alternatives --set g++ /usr/local/gcc-14/bin/g++

# --- vcpkg ---
export VCPKG_ROOT=~/vcpkg
git clone https://github.com/Microsoft/vcpkg.git $VCPKG_ROOT
cd $VCPKG_ROOT && ./bootstrap-vcpkg.sh
echo 'export VCPKG_ROOT=~/vcpkg' >> ~/.bashrc
echo 'export PATH="$VCPKG_ROOT:$PATH"' >> ~/.bashrc
cd ~/repos

# --- GCC14 libstdc++リンク ---
sudo ln -sf /usr/local/gcc-14/lib64/libstdc++.so* /usr/lib/x86_64-linux-gnu/

# --- LichtFeld-Studio ソース取得 ---
git clone --recursive https://github.com/MrNeRF/LichtFeld-Studio.git
cd LichtFeld-Studio

# --- 環境変数 ---
if ! grep -q "gcc-14" ~/.bashrc; then
  echo 'export CC=/usr/local/gcc-14/bin/gcc' >> ~/.bashrc
  echo 'export CXX=/usr/local/gcc-14/bin/g++' >> ~/.bashrc
  echo 'export CUDA_HOME=/usr/local/cuda-12.8' >> ~/.bashrc
  echo 'export CUDACXX=/usr/local/cuda-12.8/bin/nvcc' >> ~/.bashrc
  echo 'export LD_LIBRARY_PATH=/usr/local/gcc-14/lib64:/usr/local/cuda-12.8/lib64${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}' >> ~/.bashrc
fi
source ~/.bashrc
export CC=/usr/local/gcc-14/bin/gcc
export CXX=/usr/local/gcc-14/bin/g++
export CUDA_HOME=/usr/local/cuda-12.8
export CUDACXX=/usr/local/cuda-12.8/bin/nvcc
export LD_LIBRARY_PATH=/usr/local/gcc-14/lib64:/usr/local/cuda-12.8/lib64:$LD_LIBRARY_PATH

# --- CUDAテスト ---
nvcc --version || { echo "❌ CUDAエラー"; exit 1; }

# --- LichtFeld-Studio ビルド ---
echo "🚧 LichtFeld-Studioビルド開始..."
rm -rf build vcpkg_installed vcpkg_buildtrees
cmake -B build \
  -DCMAKE_BUILD_TYPE=Release \
  -G "Unix Makefiles" \
  -DCMAKE_TOOLCHAIN_FILE="$VCPKG_ROOT/scripts/buildsystems/vcpkg.cmake" \
  -DCMAKE_CUDA_COMPILER="$CUDACXX" \
  -DCMAKE_CUDA_ARCHITECTURES="native" \
  -DCMAKE_C_COMPILER="$CC" \
  -DCMAKE_CXX_COMPILER="$CXX" \
  -DCMAKE_INSTALL_RPATH="/usr/local/gcc-14/lib64:/usr/local/cuda-12.8/lib64" \
  -DCMAKE_BUILD_RPATH="/usr/local/gcc-14/lib64:/usr/local/cuda-12.8/lib64"
make -j"$(nproc)" -C build VERBOSE=1

echo "✅ ビルド完了: $(pwd)/build/LichtFeld-Studio"
file build/LichtFeld-Studio

# --- 再配布用ZIP作成 ---
echo "📦 再配布ZIP作成中..."
DIST_DIR=~/repos/LichtFeld-Studio/dist/LichtFeld-Studio
mkdir -p "$DIST_DIR/libs"

# 本体コピー
cp build/LichtFeld-Studio "$DIST_DIR/"

# 依存libコピー（非標準パスのもの）
cp /usr/local/gcc-14/lib64/libstdc++.so* "$DIST_DIR/libs/"
cp /usr/local/cuda-12.8/lib64/libcudart.so* "$DIST_DIR/libs/" || true
cp /usr/local/cuda-12.8/lib64/libcublas.so* "$DIST_DIR/libs/" || true
cp /usr/local/cuda-12.8/lib64/libnvrtc.so* "$DIST_DIR/libs/" || true

# 起動スクリプト生成
cat > "$DIST_DIR/run.sh" <<'EOS'
#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
export LD_LIBRARY_PATH="$SCRIPT_DIR/libs:$LD_LIBRARY_PATH"
"$SCRIPT_DIR/LichtFeld-Studio" "$@"
EOS
chmod +x "$DIST_DIR/run.sh"

# README生成
cat > "$DIST_DIR/README.txt" <<'EOS'
LichtFeld-Studio for Ubuntu 22.04 (CUDA12.8 + GCC14 同梱版)
----------------------------------------------------------
実行方法:
  cd LichtFeld-Studio
  ./run.sh

必要条件:
  ・NVIDIA GPU + ドライバ version 570 以上
  ・Ubuntu 22.04 環境
EOS

cd "$(dirname "$DIST_DIR")"
zip -r LichtFeld-Studio_Ubuntu22_CUDA12.8.zip LichtFeld-Studio >/dev/null

echo ""
echo "🎉 再配布ZIP作成完了: $(dirname "$DIST_DIR")/LichtFeld-Studio_Ubuntu22_CUDA12.8.zip"
echo "📦 解凍して ./run.sh ですぐ実行可能（lib同梱済み）"
echo ""
echo "=== ✅ LichtFeld-Studio ビルド＆配布パッケージ生成 完了 ==="
