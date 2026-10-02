Pod::Spec.new do |s|
  s.name     = 'cmark-gfm'
  # Upstream tag 0.29.0.gfm.13, written in a form CocoaPods accepts.
  s.version  = '0.29.0.13'
  s.summary  = "GitHub's CommonMark + GFM parser, vendored with MacDown's patches."
  s.description = <<-DESC
    cmark-gfm 0.29.0.gfm.13 with three small patches for MacDown (underscore
    emphasis flag and backslash math). See MACDOWN.md for details.
  DESC
  s.homepage = 'https://github.com/github/cmark-gfm'
  s.license  = { :type => 'BSD-2-Clause', :file => 'COPYING' }
  s.author   = { 'John MacFarlane' => 'jgm@berkeley.edu', 'GitHub' => 'opensource@github.com' }
  s.source   = { :git => 'https://github.com/github/cmark-gfm.git',
                 :tag => '0.29.0.gfm.13' }
  s.platform = :osx, '13.0'

  # MacDown's own syntax extensions (MacDown/Code/Markdown) need the internal
  # headers too, so every header is published under <cmark-gfm/...>.
  s.source_files  = 'src/*.{c,h}', 'extensions/*.{c,h}', 'generated/*.h'
  s.preserve_paths = 'src/*.inc', 'MACDOWN.md'
  s.requires_arc  = false
end
