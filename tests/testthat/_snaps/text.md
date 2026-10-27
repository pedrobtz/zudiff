# unified output is GNU's format

    Code
      cat(diff_unified(diff_text(old, new), old_name = "a/f.txt", new_name = "b/f.txt"))
    Output
      --- a/f.txt
      +++ b/f.txt
      @@ -2,7 +2,7 @@
       line 2
       line 3
       line 4
      -line 5
      +line five
       line 6
       line 7
       line 8
      @@ -14,7 +14,6 @@
       line 14
       line 15
       line 16
      -line 17
       line 18
       line 19
       line 20

---

    Code
      cat(diff_unified(diff_text(old, new), context = 0))
    Output
      --- old
      +++ new
      @@ -5 +5 @@
      -line 5
      +line five
      @@ -17 +16,0 @@
      -line 17

---

    Code
      cat(diff_unified(diff_text("a\nb", "a\nb\n")))
    Output
      --- old
      +++ new
      @@ -1,2 +1,2 @@
       a
      -b
      \ No newline at end of file
      +b

---

    Code
      cat(diff_unified(diff_text("", "x\n")))
    Output
      --- old
      +++ new
      @@ -0,0 +1 @@
      +x

---

    Code
      cat(diff_unified(diff_vec(c(1.5, 2, NA), c(1.5, 2.25, NA))))
    Output
      --- old
      +++ new
      @@ -1,3 +1,3 @@
       1.5
      -2
      +2.25
       NA

# the print method caps and clips

    Code
      print(d)
    Output
      <zudiff: myers, edit distance 2>
      @@ -1,3 +1,3 @@
       a
      -b
      +x
       c

---

    Code
      print(long)
    Output
      <zudiff: myers, edit distance 400>
      @@ -1,200 +1,200 @@
      -1
      -2
      -3
      -4
      -5
      -6
      -7
      -8
      -9
      -10
      -11
      -12
      -13
      -14
      -15
      -16
      -17
      -18
      -19
      -20
      -21
      -22
      -23
      -24
      -25
      -26
      -27
      -28
      -29
      -30
      -31
      -32
      -33
      -34
      -35
      -36
      -37
      -38
      -39
      -40
      -41
      -42
      -43
      -44
      -45
      -46
      -47
      -48
      -49
      ... 351 more lines; use `print(d, n = Inf)` to see them all.

---

    Code
      print(diff_vec(strrep("w", 100), strrep(
        "v", 100)))
    Output
      <zudiff: myers, edit distance 2>
      @@ -1 +1 @@
      -wwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwww...
      +vvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvv...

---

    Code
      print(diff_vec(1:3, 1:3))
    Output
      <zudiff: no differences>

