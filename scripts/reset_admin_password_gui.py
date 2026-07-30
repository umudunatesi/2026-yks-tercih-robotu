import argparse
import shutil
import sqlite3
import sys
from datetime import datetime
from pathlib import Path
from tkinter import Tk, messagebox, ttk


PROJECT_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(PROJECT_ROOT / "backend"))

from app.core.security import hash_password


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--database", type=Path, required=True)
    parser.add_argument("--email", required=True)
    args = parser.parse_args()

    database = args.database.resolve()
    email = args.email.strip().casefold()

    root = Tk()
    root.title("2026 YKS Tercih Robotu - Şifre Sıfırlama")
    root.geometry("470x265")
    root.resizable(False, False)

    frame = ttk.Frame(root, padding=24)
    frame.pack(fill="both", expand=True)
    ttk.Label(frame, text="Yönetici şifresini yenile", font=("Segoe UI", 15, "bold")).pack(
        anchor="w"
    )
    ttk.Label(frame, text=f"Giriş e-postası: {email}").pack(anchor="w", pady=(8, 16))

    password = ttk.Entry(frame, show="●", font=("Segoe UI", 11))
    confirm = ttk.Entry(frame, show="●", font=("Segoe UI", 11))
    ttk.Label(frame, text="Yeni şifre (en az 10 karakter)").pack(anchor="w")
    password.pack(fill="x", pady=(3, 10))
    ttk.Label(frame, text="Yeni şifre tekrar").pack(anchor="w")
    confirm.pack(fill="x", pady=(3, 16))

    def save() -> None:
        value = password.get()
        if len(value) < 10:
            messagebox.showerror("Geçersiz şifre", "Şifre en az 10 karakter olmalıdır.")
            return
        if value != confirm.get():
            messagebox.showerror("Şifreler eşleşmiyor", "İki alana aynı şifreyi yazın.")
            return
        if not database.exists():
            messagebox.showerror("Veritabanı bulunamadı", str(database))
            return

        backup_dir = database.parent.parent / "backups"
        backup_dir.mkdir(parents=True, exist_ok=True)
        backup = backup_dir / f"yks-before-password-reset-{datetime.now():%Y%m%d-%H%M%S}.db"
        shutil.copy2(database, backup)

        with sqlite3.connect(database) as connection:
            cursor = connection.execute(
                """
                UPDATE users
                   SET password_hash = ?, is_active = 1
                 WHERE lower(email) = ?
                """,
                (hash_password(value), email),
            )
            if cursor.rowcount != 1:
                messagebox.showerror("Hesap bulunamadı", email)
                return
            connection.commit()

        messagebox.showinfo(
            "Şifre yenilendi",
            f"Şifreniz kaydedildi.\n\nGiriş e-postası:\n{email}",
        )
        root.destroy()

    ttk.Button(frame, text="Şifreyi kaydet", command=save).pack(anchor="e")
    password.focus_set()
    root.mainloop()


if __name__ == "__main__":
    main()
