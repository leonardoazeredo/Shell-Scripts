# macOS Development Environment Setup

This guide provides a complete workflow for setting up a new macOS machine from scratch. The process is designed to be as automated as possible, using a powerful setup script to install all necessary software and then deploying a personalized `dotfiles` configuration.

The philosophy is simple:
1.  **Automate Everything Possible:** A single script installs applications, command-line tools, language runtimes, and shell configurations.
2.  **Secure and Interactive Logins:** The script handles automated logins to developer services securely using Bitwarden and guides you through the necessary manual GUI logins.
3.  **Personalize with Dotfiles:** Once the base system is ready, you will deploy your own custom configuration files for a familiar and efficient environment.

## Prerequisites

Before you begin, ensure you have the following accounts and information ready:

*   **Apple ID:** Your username and password for the Mac App Store.
*   **GitHub Account:** A Personal Access Token (PAT) with `repo`, `read:org`, and `gist` scopes.
*   **Docker Hub Account:** Your username and an Access Token.
*   **Bitwarden Account:** Your master password and 2FA/OTP code. Your vault must be pre-populated with the following **exact** item names:
    *   `[ ]` A "Login" item named **`GitHub PAT`** with the token in the *password* field.
    *   `[ ]` A "Login" item named **`Docker Hub`** with your username and Access Token.
    *   `[ ]` A "Login" item named **`Apple ID`** with your username and password.

## Part 1: The Automated Setup Script

This first stage involves running the main `mac_setup.sh` script. This will perform the bulk of the installation work.

**1. Open the Terminal**
The first thing to do on a new Mac is open the Terminal app. You can find it in `/Applications/Utilities/` or by searching with Spotlight (`CMD + Space`).

**2. Download and Run the Script**
You need to get the `mac_setup.sh` script onto the new machine. The easiest way is to download it directly from the web.

*   **Run this command to download and execute the script in one go:**
    ```sh
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/leonardoazeredo/Shell-Scripts/refs/heads/master/mac_setup.sh)"
    ```
    *(**Note:** Replace the URL with the raw link to your `mac_setup.sh` file on GitHub, a Gist, or another host.)*

**3. What to Expect During the Script's Execution**
The script is designed to be mostly non-interactive, but it will pause for a few key actions:

*   **`sudo` Password Prompts:** The script needs administrative privileges for certain actions (like installing `SourceGit`). You will be prompted for your Mac's user password.
*   **The Interactive Finale:** Near the end of the script, all interactive steps are grouped together:
    1.  **Bitwarden Login:** You will be prompted for your Bitwarden email, master password, and 2FA code. This is used to securely automate the next steps.
    2.  **CLI Logins:** The script will automatically log in to GitHub and Docker Hub.
    3.  **App Store Login:** The script will ask if you want to install App Store apps. If you agree, it will display your Apple ID credentials (fetched from Bitwarden) for convenience and then begin the installation, which will trigger the system's GUI login prompt for you to complete.

## Part 2: Deploying Your Dotfiles

Once the setup script finishes, your machine has all the tools, but it's using a generic shell configuration. This next part deploys your personalized `dotfiles`.

**1. Clone Your Bare Repository**
This command clones your existing `dotfiles` repository into a hidden directory in your home folder. Replace `your-username` with your GitHub username.

```sh
git clone --bare git@github.com:your-username/dotfiles.git $HOME/.dotfiles
```

> **SSH Host Key Verification**
> The first time you connect to GitHub via SSH, you will see this message:
> ```
> The authenticity of host 'github.com' can't be established.
> ED25519 key fingerprint is SHA256:+DiM3ffdV6TuJJkkp2jsG/zLDA0zPMSvSmkt3UvC0qC.
> Are you sure you want to continue connecting (yes/no/[fingerprint])?
> ```
> This is a normal security measure. Type **`yes`** and press **Enter** to permanently trust GitHub's key.

**2. Set Up the `dotgit` Alias**
This powerful alias allows you to use `git` to manage your home directory files.

```sh
# Add the alias to your newly created .zshrc file
echo "alias dotgit='/usr/bin/git --git-dir=$HOME/.dotfiles/ --work-tree=$HOME'" >> ~/.zshrc

# Reload your shell to activate the alias
source ~/.zshrc
```

**3. Configure the `dotgit` Repository**
This one-time command tells your `dotgit` alias to ignore all the other untracked files in your home directory, keeping its status clean.

```sh
dotgit config --local status.showUntrackedFiles no
```

**4. Deploy Your Configuration Files**
The final step is to "check out" your configuration files into your home directory. This may overwrite some default files created by the setup script (like `.zshrc`), which is what we want.

```sh
# This command attempts to check out your files. It may fail if there are conflicts.
# The `|| true` ensures the script doesn't exit if there are no conflicts.
dotgit checkout || true
```
*If the command complains about files being overwritten, you can safely back them up and re-run the checkout:*
```sh
# Create a backup directory
mkdir -p .dotfiles-backup

# Move conflicting files to the backup
dotgit checkout 2>&1 | grep -E "^\s+" | awk {'print $1'} | xargs -I{} mv {} .dotfiles-backup/{}

# Run checkout again - it will succeed this time
dotgit checkout
```

**5. Reload Your Shell**
Your custom configuration is now in place. Reload the shell one last time to see your personalized environment come to life.

```sh
source ~/.zshrc
```

---

## Setup Complete!

Your new macOS machine is now a perfect mirror of your previous setup, complete with all applications, developer tools, and your personalized `dotfiles` configuration.

*   The last step is to run **`p10k configure`** in your terminal to set up your Powerlevel10k prompt style if you haven't already.
