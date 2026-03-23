# LFS_for_Ubuntu
LFS_for_ubuntu

# How to use
```
git clone https://github.com/tohohogisu/LFS_for_Ubuntu.git
cd LFS_for_Ubuntu
chmod +x build_lichtfeld_full.sh && ./build_lichtfeld_full.sh
```

# グループごと
0. 下準備（共通）
```
cd ~
mkdir -p repos
cd repos
```
1. NVIDIA Driver 570 + CUDA 12.8
```
# 1-1. NVIDIA CUDA リポジトリ追加（keyring）
cd ~/repos
wget https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/x86_64/cuda-keyring_1.1-1_all.deb
sudo dpkg -i cuda-keyring_1.1-1_all.deb
sudo apt update -y

# 1-2. NVIDIA Driver 570（open）
sudo apt install -y nvidia-driver-570-open

# 1-3. CUDA 12.8 Toolkit
sudo apt install -y cuda-toolkit-12-8

# 1-4. CUDA 用 PATH 設定
if ! grep -q "cuda-12.8" ~/.bashrc; then
  echo 'export PATH=/usr/local/cuda-12.8/bin${PATH:+:${PATH}}' >> ~/.bashrc
  echo 'export LD_LIBRARY_PATH=/usr/local/cuda-12.8/lib64${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}' >> ~/.bashrc
fi
source ~/.bashrc
export PATH=/usr/local/cuda-12.8/bin:$PATH
export CUDACXX=/usr/local/cuda-12.8/bin/nvcc
```
2. CMake とビルド必須ツール
```
# 2-1. CMake（snap 版）
sudo snap install cmake --classic

# 2-2. ビルドツール + SDL3 依存ライブラリ
sudo apt update && sudo apt install -y \
  build-essential flex bison libgmp3-dev libmpc-dev libmpfr-dev libisl-dev texinfo \
  git ninja-build pkg-config curl zip unzip nasm \
  libx11-dev libxft-dev libxext-dev \
  libxrandr-dev libxinerama-dev libxcursor-dev libxi-dev \
  libgl1-mesa-dev libglu1-mesa-dev libegl1-mesa-dev \
  libwayland-dev libxkbcommon-dev libibus-1.0-dev \
  autoconf autoconf-archive automake libtool m4 gettext libffi-dev libssl-dev
```
GCC 14.3.0 のビルド＆インストール
```
# 3-1. スワップ追加（メモリ対策）
cd ~/repos
sudo fallocate -l 16G /swapfile || true
sudo chmod 600 /swapfile || true
sudo mkswap /swapfile || true
sudo swapon /swapfile || true
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab >/dev/null

# 3-2. GCC 14.3.0 ソース取得
curl -fLO https://ftp.gnu.org/gnu/gcc/gcc-14.3.0/gcc-14.3.0.tar.xz
tar -xf gcc-14.3.0.tar.xz
cd gcc-14.3.0

# 3-3. 依存ライブラリ取得＆ビルド
./contrib/download_prerequisites
mkdir build && cd build
../configure --prefix=/usr/local/gcc-14 --disable-multilib --enable-languages=c,c++
make -j"$(nproc)"
sudo make install

# 3-4. システムの gcc/g++ を GCC14 に切り替え
cd ~/repos
sudo update-alternatives --install /usr/bin/gcc gcc /usr/local/gcc-14/bin/gcc 140
sudo update-alternatives --install /usr/bin/g++ g++ /usr/local/gcc-14/bin/g++ 140
sudo update-alternatives --set gcc /usr/local/gcc-14/bin/gcc
sudo update-alternatives --set g++ /usr/local/gcc-14/bin/g++

# 3-5. libstdc++ をシステムから見えるようにリンク
sudo ln -sf /usr/local/gcc-14/lib64/libstdc++.so* /usr/lib/x86_64-linux-gnu/
```
vcpkg のセットアップ
```
# 4-1. Git HTTP 設定（Vast などでの clone 安定化）
git config --global http.version HTTP/1.1
git config --global http.postBuffer 524288000
git config --global http.lowSpeedLimit 0
git config --global http.lowSpeedTime 999999

# 4-2. vcpkg クローン＆ブートストラップ
export VCPKG_ROOT=~/vcpkg
rm -rf "$VCPKG_ROOT"
git clone https://github.com/Microsoft/vcpkg.git "$VCPKG_ROOT"
cd "$VCPKG_ROOT"
./bootstrap-vcpkg.sh

# 4-3. 環境変数永続化
echo 'export VCPKG_ROOT=~/vcpkg' >> ~/.bashrc
echo 'export PATH="$VCPKG_ROOT:$PATH"' >> ~/.bashrc
cd ~/repos
```
LichtFeld-Studio ソース取得と環境変数
```
# 5-1. リポジトリ取得
cd ~/repos
rm -rf LichtFeld-Studio
git clone --recursive https://github.com/MrNeRF/LichtFeld-Studio.git
cd LichtFeld-Studio

# 5-2. コンパイラ・CUDA 環境変数
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

# 5-3. CUDA 確認
nvcc --version
```
LichtFeld-Studio のビルド
```
cd ~/repos/LichtFeld-Studio

# 6-1. 以前のビルドを掃除
rm -rf build vcpkg_installed vcpkg_buildtrees

# 6-2. CMake 設定
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

# 6-3. ビルド本体
make -j"$(nproc)" -C build VERBOSE=1
```
lib 同梱 ZIP の作成
```
cd ~/repos/LichtFeld-Studio

DIST_DIR=~/repos/LichtFeld-Studio/dist/LichtFeld-Studio
mkdir -p "$DIST_DIR/libs"

# 7-1. バイナリコピー
cp build/LichtFeld-Studio "$DIST_DIR/"

# 7-2. 依存ライブラリコピー
cp /usr/local/gcc-14/lib64/libstdc++.so* "$DIST_DIR/libs/"
cp /usr/local/cuda-12.8/lib64/libcudart.so* "$DIST_DIR/libs/" || true
cp /usr/local/cuda-12.8/lib64/libcublas.so* "$DIST_DIR/libs/" || true
cp /usr/local/cuda-12.8/lib64/libnvrtc.so* "$DIST_DIR/libs/" || true

# 7-3. 起動スクリプト
cat > "$DIST_DIR/run.sh" <<'EOS'
#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
export LD_LIBRARY_PATH="$SCRIPT_DIR/libs:$LD_LIBRARY_PATH"
"$SCRIPT_DIR/LichtFeld-Studio" "$@"
EOS
chmod +x "$DIST_DIR/run.sh"

# 7-4. README
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

# 7-5. ZIP 作成
cd "$(dirname "$DIST_DIR")"
zip -r LichtFeld-Studio_Ubuntu22_CUDA12.8.zip LichtFeld-Studio
```
   
