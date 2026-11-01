// Features/Audiobooks/Views/BookCoverView.swift
// Отображает обложку книги. Изображение загружается асинхронно, не в полном размере.

import SwiftUI

struct BookCoverView: View {
    let book: AudioBook
    let size: CGFloat

    @State private var image: UIImage?

    var body: some View {
        Group {
            if let img = image {
                Image(uiImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Image(systemName: "headphones")
                    .font(.system(size: size * 0.4))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(.systemGray5))
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.12))
        .task { await loadCover() }
        .accessibilityHidden(true)
    }

    private func loadCover() async {
        guard let coverName = book.coverFileName else { return }
        let dir = BookLibrary.audioBooksDirectory.appending(path: book.folderName)
        let url = dir.appending(path: coverName)

        // Декодируем в уменьшенном размере, не в полный
        let targetPoints = size * 2 // @2x
        let task = Task.detached {
            guard let data = try? Data(contentsOf: url) else { return UIImage?.none }
            let opts: [CFString: Any] = [
                kCGImageSourceShouldCache: false,
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: Int(targetPoints),
            ]
            guard let src = CGImageSourceCreateWithData(data as CFData, nil),
                  let thumb = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary)
            else { return UIImage?.none }
            return UIImage(cgImage: thumb)
        }
        image = await task.value
    }
}
